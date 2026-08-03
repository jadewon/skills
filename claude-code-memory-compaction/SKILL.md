---
name: claude-code-memory-compaction
description: Compact a Claude Code auto-memory index that is at or near its startup limit (200 lines / 25KB), promoting project-independent guidance into ~/.claude/rules/ so it stops being trapped in one project. Use when the memory index is over its read limit, when Claude Code warns the index is near a limit, or on "메모리 상한", "메모리 정리", "memory index too big".
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
index lines whose file is gone, and files nothing in the directory can reach.

## Decide, per entry

Read the entry before choosing. Four outcomes, and most entries are not promotions:

| Entry | Outcome |
|---|---|
| Guidance that applies to specific file types or directories | promote with `--paths` |
| A guardrail with a repeat-violation history, applying everywhere | promote with no `--paths` |
| Guidance that is genuinely about this one repo | keep in memory; shorten the index line |
| Two entries saying the same thing | merge into one file, delete the other |
| Wrong, obsolete, or already true of the code | delete the file and its index line |

The trap: a rule **without** `paths` loads its whole body into every session, while a memory
entry only costs its one index line until something reads it. Promoting a rarely-needed
note without a `paths` scope makes context worse, not better. Reserve unscoped promotion
for guidance that must not be left to probabilistic recall, and check `~/.claude/CLAUDE.md`
for the same instruction before writing it — if it is already there, delete the memory
entry instead of promoting a duplicate.

`project` and `reference` entries stay where they are. Their scoping to one repository is
correct, and moving them into rules would leak one project's context into every other.

## Files nothing can reach

Reachability is transitive, so `measure` walks it that way: it starts at the index and
follows every `file.md` mention and `[[wiki-link]]`, then does the same from each file it
lands on. A merged file that absorbed a dozen entries and names them in its body keeps all
of them reachable. That two-level shape — index line points at a group file, group file
names its members — is the cheapest way to hold many entries under a 200-line index, and
counting only direct index links would report those members as orphans when they are not.

Treat the result as a lower bound. A filename sitting in another file's prose counts as a
reference whether or not a reader would ever follow it, so a dead file can stay unflagged.
Code spans are excluded from the walk, since an example command or a "renamed from old.md"
aside is the common accidental mention — but the count is evidence, not proof.

What the walk does not reach is genuinely inert: it never loads at session start and nothing
leads to it, so no future session will see it. Read each one and pick: merge it into a group
file that is already indexed, add an index line if it deserves its own, promote it if it is
guidance for every session, or delete it. Deleting is the common answer and the honest one —
a file nothing can reach is not a backup. What is **not** a fix is restoring an index line
for each: one line apiece is exactly what the 200-line limit is made of.

## Promote

```bash
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" promote feedback_try_before_asking.md \
  --paths "src/**/*.ts,tests/**/*.ts"        # omit --paths for an always-loaded rule
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" promote <file> --dry-run   # preview only
```

Writes `~/.claude/rules/<name>.md` (the `feedback_` prefix is dropped, `_` becomes `-`),
removes the source file, and deletes its index line by exact-string filter. It refuses to
overwrite an existing rule — merge those by hand. Rules are written in English like the
memory files they come from. Any other memory file that named the promoted entry — as a
`[[wiki-link]]` or as a bare filename — is reported so you can repoint it at the rule, and
so is anything the rule itself still names, since a rule cannot resolve those.

Do not batch-promote everything of one type. Each promotion is a decision about whether
that text is worth its cost in every future session.

## Verify

```bash
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" verify
```

Re-measures the index and lists `~/.claude/rules/`, marking each rule always-loaded or
paths-scoped. Confirm the index is under both limits and that no rule is unscoped by
accident. In the next session, `/context` shows the rules that actually loaded.

`memory_index.py selftest` pins how references are parsed — sentence-final names, wiki-links
with an anchor or alias, code spans, double extensions. Run it after editing that parsing:
each case there is a bug this tool shipped with once, and every one of them turned a live
file into a reported orphan.
