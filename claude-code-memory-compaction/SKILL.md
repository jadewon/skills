---
name: claude-code-memory-compaction
description: Compact a Claude Code auto-memory index that is at or near its startup limit (200 lines / 25KB), promoting project-independent guidance into ~/.claude/rules/ so it stops being trapped in one project, and merging several entries into one group file without leaving the sources behind. Use when the memory index is over its read limit, when Claude Code warns the index is near a limit, when auditing a memory store for duplicate bodies or broken pointers, or on "메모리 상한", "메모리 정리", "memory index too big".
disable-model-invocation: false
argument-hint: "[--dir <memory dir>] — runs against the current project's auto memory by default"
allowed-tools: Bash, Read, Write, Edit
---

# claude-code-memory-compaction

Only the first 200 lines or 25KB of `MEMORY.md` (whichever comes first) load at session
start; everything past that is dropped silently on the next load. Topic files are not
loaded at all until read on demand. So an index at the limit is a routing problem, not a
storage problem: the fix is deciding what each entry should become, not trimming words.

Auto memory is also **per repository**. Guidance about how to work — the `feedback` type —
is usually project-independent, yet it lives in one project's directory and is invisible
everywhere else. Promoting those entries to `~/.claude/rules/` is what actually removes
pressure from the index, because it moves them out of the counted file entirely.

## Run

```bash
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" measure
```

It resolves the memory directory the way Claude Code does — `autoMemoryDirectory` from the
settings chain if set, otherwise the slug of the git root — then reports lines and bytes
against both limits, counting only what loads (frontmatter and block-level HTML comments
are stripped first, matching Claude Code >= 2.1.211). It also lists `feedback` entries,
index lines whose file is gone, files nothing in the directory can reach, shadow copies
(a body that lives in two files, one of them un-indexed), and pointers that land on nothing.

## Decide, per entry

Read the entry before choosing. Most entries are not promotions. Every outcome that copies a
body somewhere else also **deletes the file it came from** — that is the one invariant here:

| Entry | Outcome |
|---|---|
| Guidance that applies to specific file types or directories | promote with `--paths` |
| A guardrail with a repeat-violation history, applying everywhere | promote with no `--paths` |
| Guidance that is genuinely about this one repo | keep in memory; shorten the index line |
| Two entries saying the same thing | merge into one file, delete the other file and its index line |
| Several small entries on one theme | absorb into a `group_*.md` — see below, the sources get deleted |
| Wrong, obsolete, or already true of the code | delete the file and its index line |

The trap: a rule **without** `paths` loads its whole body into every session, while a memory
entry only costs its one index line until something reads it. Promoting a rarely-needed
note without a `paths` scope makes context worse, not better. Reserve unscoped promotion
for guidance that must not be left to probabilistic recall, and check `~/.claude/CLAUDE.md`
for the same instruction before writing it — if it is already there, delete the memory
entry instead of promoting a duplicate.

`project` and `reference` entries stay where they are. Their scoping to one repository is
correct, and moving them into rules would leak one project's context into every other.

## Absorb into a group file

Merging N entries into one `group_*.md` is how the index stays under 200 lines: N facts cost
one index line. The merge is a **move, not a copy**, and it is not done until the source is
gone. Four steps, and step 2 is the one that gets skipped:

1. Paste the body into the group file under a heading that names the fact.
2. Delete the source file.
3. Delete the source's own index line from `MEMORY.md`.
4. Repoint whatever named the source at the group file — `measure` lists what now dangles.

There is exactly one alternative, for a standalone too long or too specific to fold in:
leave the file and give it **its own `MEMORY.md` index line**. Reachable, unambiguous, one
line. Those are the only two endings an absorb has.

What is **not** an ending is leaving the source on disk with its body already copied and a
prose note in the group file saying which copy is authoritative. Nothing reads a note like
that. What a later session gets handed by semble or grep is the standalone, so that is the
copy it edits — and the standalone is the one nothing loads. This is measured, not
hypothetical: it produced 53 un-indexed shadow copies totalling 215KB, 50 of them exact
substrings of their group copy, and every reachability report stayed green the whole time.
`measure` now names them and `verify` exits non-zero while one is on disk.

## Files nothing can reach

Reachability is transitive, so `measure` walks it that way: it starts at the index and
follows every `file.md` mention and `[[wiki-link]]`, then does the same from each file it
lands on. A link resolves against the target's `name:` frontmatter first and its filename
second, because the two disagree constantly — `[[dior-event-loop-fs-io-mitigation]]` is
`project_dior_event_loop_fs_io.md`. Matching on filenames alone calls that link dead and its
target an orphan, and the orphan list is what a caller deletes from.

Two-level indirection — index line points at a group file, the group file names a sibling —
is deliberate, and counting only direct index links would report those siblings as orphans
when they are not. But being named in a group body buys **reachability, nothing else**. It
does not make the standalone authoritative and it does not excuse a duplicate body; that is
the absorb rule above, and `verify` enforces it separately.

Treat the reachability result as a lower bound. A filename sitting in another file's prose
counts as a reference whether or not a reader would ever follow it, so a dead file can stay
unflagged. Code spans are excluded from the walk, since an example command or a "renamed
from old.md" aside is the common accidental mention — but the count is evidence, not proof.

What the walk does not reach is genuinely inert: it never loads at session start and nothing
leads to it, so no future session will see it. Read each one and pick: fold it into an
indexed group file **and delete it**, give it its own index line, promote it if it is
guidance for every session, or delete it outright. Deleting is the common answer and the
honest one — a file nothing can reach is not a backup. What is **not** a fix is restoring an
index line for each: one line apiece is exactly what the 200-line limit is made of.

## Promote

```bash
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" promote feedback_try_before_asking.md \
  --paths "src/**/*.ts,tests/**/*.ts"        # omit --paths for an always-loaded rule
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" promote <file> --dry-run   # preview only
```

Writes `~/.claude/rules/<name>.md` (the `feedback_` prefix is dropped, `_` becomes `-`),
removes the source file, and deletes its index line by exact-string filter — the same
move-not-copy invariant the absorb section states, done for you here. It refuses to
overwrite an existing rule — merge those by hand. Rules are written in English like the
memory files they come from. Any other memory file that named the promoted entry — as a
`[[wiki-link]]` or as a bare filename — is reported so you can repoint it at the rule, and
so is anything the rule itself still names, since a rule cannot resolve those.

Do not batch-promote everything of one type. Each promotion is a decision about whether
that text is worth its cost in every future session.

## Instruction budget

Claude Code warns when the instruction files it loads at startup exceed 150,000 chars (JS
string length). Those files are `~/.claude/CLAUDE.md`, the unscoped rules, and the
`CLAUDE.md`, `CLAUDE.local.md`, `.claude/CLAUDE.md` and unscoped `.claude/rules/**` of every
directory from the session's directory up to `/`. A rule with a non-empty `paths:` does not
count. `MEMORY.md` does not count either. `measure` and `verify` list each counted file and
the total: `[ok]` below 130k, `[warn]` from 130k, `[over]` from 150k. These states are
reported only. They do not change `verify`'s exit code, which is 1 only for shadow copies.

`--project <dir>` selects the session directory (the default is cwd). `promote` refuses an
unscoped rule that would take the total past **140,000**. Scope that rule with `--paths`, or
trim the files first. `promote` checks one directory chain only. An unscoped user rule loads
in every project, so run `promote` from the project with the largest chain, or pass that
project with `--project`.

## Verify

```bash
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" verify   # exit 1 while a shadow copy survives
```

Re-measures the index, names any shadow copy and any dangling pointer, and lists
`~/.claude/rules/` recursively, marking each rule always-loaded or paths-scoped. A compaction run is
finished when this exits 0 — not when the reachability line reads "all reachable", which is
what was on screen for all 53 shadows. Confirm the index is under both limits and that no
rule is unscoped by accident. In the next session, `/context` shows the rules that loaded.

Only shadow copies fail the run. Dangling pointers are reported, because a link to a deleted
file is allowed by the memory format and repairing prose is a judgement call — but a group
file whose member list points at nothing has lost the record of what it absorbed, so close
them in the same pass.

Both pointer syntaxes are checked. Bodies use `[[wikilink]]` and bare `file.md` in similar
numbers, yet only the bracketed half is greppable, so a hand audit of `[[` passes a store
whose bare pointers are dead — one survived exactly that way in
`group_feedback_reasoning_patterns.md`. A dead `[[wiki-link]]` is always reported, since that
syntax means nothing else here; a bare mention is reported only when its name carries one of
the store's own filename prefixes, because bodies cite repo docs (`CLAUDE.md`,
`deploy-notes.md`) far more often than they cite siblings.

`memory_index.py selftest` pins how references are parsed — sentence-final names, wiki-links
with an anchor or alias, code spans, double extensions — and the checks built on that
parsing: `name:` resolution, shadow detection (verbatim and reworded, an indexed file
exempt, a short body below the floor exempt), the dangling report in both syntaxes,
`verify`'s exit code, which files the instruction budget counts, and the promote ceiling.
Run it after editing any of them: each parsing case is a bug this tool shipped with once,
and every one of them turned a live file into a reported orphan.
