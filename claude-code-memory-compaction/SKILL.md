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
index lines whose file is gone, and files on disk that no index line mentions.

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

## Files with no index line

`measure` reports these separately, and a long-lived project can have more of them than
indexed entries. An index line is a file's only entry point: without one the file never
loads at session start and nothing points at it later, so its content is inert.

Restoring index lines is **not** the default fix — one line each is exactly what the 200-line
limit is made of, so a bulk restore trades a silent problem for an over-limit index. Read
each file and pick: promote it if it is guidance that belongs in every session, add an index
line if it is project knowledge worth an entry, delete it if it is stale, wrong, or already
covered by another entry. Deleting is the common answer, and it is the honest one — an entry
nothing can reach is not a backup.

## Promote

```bash
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" promote feedback_try_before_asking.md \
  --paths "src/**/*.ts,tests/**/*.ts"        # omit --paths for an always-loaded rule
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" promote <file> --dry-run   # preview only
```

Writes `~/.claude/rules/<name>.md` (the `feedback_` prefix is dropped, `_` becomes `-`),
removes the source file, and deletes its index line by exact-string filter. It refuses to
overwrite an existing rule — merge those by hand. Rules are written in English like the
memory files they come from; a `[[wiki-link]]` in another memory file pointing at a promoted
entry is reported so you can repoint it at the rule.

Do not batch-promote everything of one type. Each promotion is a decision about whether
that text is worth its cost in every future session.

## Verify

```bash
python3 "${CLAUDE_SKILL_DIR}/memory_index.py" verify
```

Re-measures the index and lists `~/.claude/rules/`, marking each rule always-loaded or
paths-scoped. Confirm the index is under both limits and that no rule is unscoped by
accident. In the next session, `/context` shows the rules that actually loaded.
