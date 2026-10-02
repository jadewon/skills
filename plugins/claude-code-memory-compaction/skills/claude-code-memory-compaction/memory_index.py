#!/usr/bin/env python3
"""memory_index.py - measure a Claude Code auto-memory index and promote entries to ~/.claude/rules/.

Subcommands:
  measure   report MEMORY.md load size against the 200-line / 25KB startup limits, and the
            startup instruction files against the 150,000-char budget
  promote   move one memory file into ~/.claude/rules/ and drop its index line
  verify    re-measure and list rules files

Only the portion of MEMORY.md that Claude Code actually loads is measured: YAML
frontmatter and block-level HTML comments are stripped before the limit check
(Claude Code >= 2.1.211), so counting the raw file overstates the size.

Python stdlib only.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import re
import subprocess
import sys

LINE_LIMIT = 200
BYTE_LIMIT = 25 * 1024
WARN_RATIO = 0.8

# Claude Code warns when the instruction files it loads at startup exceed 150,000 chars
# in total, measured as JS string length. MEMORY.md is not part of that total.
BUDGET_WARN = 130_000
BUDGET_LIMIT = 150_000
# promote refuses to push the always-loaded total past this, leaving headroom below the
# warning for the CLAUDE.md edits that happen between compaction runs.
PROMOTE_CEILING = 140_000

HOME = os.path.expanduser("~")
RULES_DIR = os.path.join(HOME, ".claude", "rules")
PROJECTS_DIR = os.path.join(HOME, ".claude", "projects")

SETTINGS_FILES = [
    (".claude/settings.local.json", "local"),
    (".claude/settings.json", "project"),
    (os.path.join(HOME, ".claude", "settings.json"), "user"),
]

FRONTMATTER_RE = re.compile(r"\A---\r?\n.*?\r?\n---[ \t]*\r?\n?", re.S)
HTML_COMMENT_RE = re.compile(r"^[ \t]*<!--.*?-->[ \t]*$\r?\n?", re.M | re.S)
INDEX_LINK_RE = re.compile(r"\(([^)]+\.md)\)")
# A memory file is reachable if anything already reachable names it - as a filename or as
# a [[wiki-link]]. Both forms matter: an index line that points at a merged group file,
# and that group file naming the entries it absorbed, form a two-level index.
# The lookaheads stop "index.md.bak" from registering its "index.md" prefix, while still
# accepting a name that ends a sentence ("see bare_mention.md.").
# The wiki branch stops at a newline: an unclosed "[[" would otherwise swallow everything
# up to the next stray "]]", taking any real filename in between with it.
REF_RE = re.compile(r"([A-Za-z0-9_.\-]+\.md)(?![A-Za-z0-9_\-])(?!\.[A-Za-z0-9])|\[\[([^\]\n]+)\]\]")
# Names inside code spans do not make a file reachable: an example command or a "renamed
# from old.md" aside mentions a filename without leading any reader to it. Counting those
# would hide a genuinely dead file.
CODE_SPAN_RE = re.compile(r"```.*?```|~~~.*?~~~|`[^`\n]*`", re.S)


# ---------------------------------------------------------------- locating


def git_root(cwd: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() or None if out.returncode == 0 else None


def configured_dir(cwd: str) -> tuple[str, str] | None:
    """autoMemoryDirectory from the settings chain, most specific first."""
    for rel, scope in SETTINGS_FILES:
        path = rel if os.path.isabs(rel) else os.path.join(cwd, rel)
        if not os.path.isfile(path):
            continue
        try:
            with open(path, encoding="utf-8") as fh:
                value = json.load(fh).get("autoMemoryDirectory")
        except (OSError, ValueError):
            continue
        if value:
            return os.path.expanduser(value), f"autoMemoryDirectory ({scope})"
    return None


def memory_dir(cwd: str) -> tuple[str, str]:
    """Resolve the auto-memory directory for cwd. Returns (path, how-it-was-found)."""
    configured = configured_dir(cwd)
    if configured:
        return configured

    root = git_root(cwd) or cwd
    root = os.path.abspath(root)
    # Claude Code slugifies the project path; both rules below have been observed.
    candidates = [
        re.sub(r"[^A-Za-z0-9]", "-", root),
        re.sub(r"[/.]", "-", root),
    ]
    for slug in candidates:
        path = os.path.join(PROJECTS_DIR, slug, "memory")
        if os.path.isdir(path):
            return path, f"project slug for {root}"
    return os.path.join(PROJECTS_DIR, candidates[0], "memory"), f"project slug for {root} (not created yet)"


# ---------------------------------------------------------------- measuring


def loaded_text(raw: str) -> str:
    """The part of an index Claude Code loads: no frontmatter, no block comments."""
    return HTML_COMMENT_RE.sub("", FRONTMATTER_RE.sub("", raw))


def split_frontmatter(raw: str) -> tuple[str, str]:
    match = FRONTMATTER_RE.match(raw)
    return (match.group(0), raw[match.end():]) if match else ("", raw)


def frontmatter_field(raw: str, field: str) -> str:
    """Read one scalar field out of a memory file's frontmatter without a YAML parser."""
    head, _ = split_frontmatter(raw)
    match = re.search(rf"^\s*{re.escape(field)}:\s*(.+?)\s*$", head, re.M)
    return match.group(1).strip().strip("\"'") if match else ""


def read(path: str) -> str:
    """Strict read, for text that gets written back or promoted into a rule."""
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def scan(path: str) -> str:
    """Lenient read, for text only inspected: one stray byte must not end the report.

    Never use this for content that will be written back - a replacement character would
    be persisted over the original byte.
    """
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def refs_detailed(text: str) -> set[tuple[str, str]]:
    """(target, syntax) this text names, ignoring code spans. syntax is "wiki" or "bare".

    Memory bodies use both forms and both are live pointers, but only "[[" is greppable,
    so a hand audit checks the bracketed half and a dead bare pointer survives it. The
    syntax is carried through so the dangling report can say which one to repair.
    """
    found = set()
    for name, wiki in REF_RE.findall(CODE_SPAN_RE.sub(" ", text)):
        # [[target#heading]] and [[target|alias]] both point at target.
        target = name or wiki.split("|")[0].split("#")[0].strip()
        if not target:
            continue
        # [[x]] and [[x.md]] both name x.md - appending unconditionally would build
        # "x.md.md", match nothing, and report a linked file as an orphan.
        found.add((os.path.basename(target if target.endswith(".md") else f"{target}.md"),
                   "bare" if name else "wiki"))
    return found


def refs(text: str) -> set[str]:
    """Memory filenames this text names, as x.md or [[x]], ignoring code spans."""
    return {target for target, _ in refs_detailed(text)}


def name_index(mem_dir: str) -> dict[str, str]:
    """`name:` frontmatter value (as <value>.md) -> filename, for every file in mem_dir.

    A link resolves against `name:`, not against the filename, and the two disagree
    constantly - [[dior-event-loop-fs-io-mitigation]] is project_dior_event_loop_fs_io.md.
    Resolving by filename alone calls that link dead and its target an orphan, and the
    orphan list is what a caller deletes from, so the mistake destroys live files.
    """
    index: dict[str, str] = {}
    for name in sorted(os.listdir(mem_dir)):
        if not name.endswith(".md") or not os.path.isfile(os.path.join(mem_dir, name)):
            continue
        declared = os.path.basename(frontmatter_field(scan(os.path.join(mem_dir, name)), "name"))
        if declared:
            index.setdefault(declared if declared.endswith(".md") else f"{declared}.md", name)
    return index


def resolve(target: str, mem_dir: str, names: dict[str, str]) -> str | None:
    """The file a reference lands on: filename first, then the `name:` index."""
    if os.path.isfile(os.path.join(mem_dir, target)):
        return target
    return names.get(target)


def reachable(mem_dir: str, index_body: str, names: dict[str, str] | None = None) -> set[str]:
    """Files a reader can get to by starting at the index and following references."""
    if names is None:
        names = name_index(mem_dir)
    seen: set[str] = set()
    frontier = refs(index_body)
    while frontier:
        target = frontier.pop()
        if target in seen:
            continue
        seen.add(target)
        landed = resolve(target, mem_dir, names)
        if landed is None:
            continue  # nothing there - dangling_refs() reports it
        seen.add(landed)
        frontier |= refs(scan(os.path.join(mem_dir, landed))) - seen
    return seen


def store_prefixes(on_disk: list[str]) -> set[str]:
    """Filename prefixes this store actually uses - feedback_, project_, group_, ...

    Read off disk rather than hardcoded. Memory bodies cite repo docs (CLAUDE.md,
    deploy-notes.md, SKILL.md) far more often than sibling entries, and those are
    correctly absent from the memory dir; reporting them buries the real breakage.
    """
    counts: dict[str, int] = {}
    for name in on_disk:
        prefix, sep, _ = name.partition("_")
        if sep:
            counts[prefix] = counts.get(prefix, 0) + 1
    return {prefix for prefix, n in counts.items() if n >= 2}


def dangling_refs(mem_dir: str, on_disk: list[str], names: dict[str, str]) -> list[dict]:
    """Pointers into this store that land on nothing, in either syntax.

    A [[wiki-link]] is store-specific syntax, so every dead one is reported. A bare
    x.md is reported only when the name carries one of the store's own prefixes -
    otherwise the report is mostly repo docs that were never meant to live here.
    """
    prefixes = store_prefixes(on_disk)
    out = []
    for source in ["MEMORY.md"] + on_disk:
        path = os.path.join(mem_dir, source)
        if not os.path.isfile(path):
            continue
        for target, syntax in sorted(refs_detailed(scan(path))):
            if target == source or resolve(target, mem_dir, names):
                continue
            if syntax == "bare" and target.partition("_")[0] not in prefixes:
                continue
            out.append({"source": source, "target": target, "syntax": syntax})
    return out


# A body under this size can sit inside a group file by coincidence; above it, a verbatim
# match is a copy. 400 chars is well under the ~4KB the observed shadow bodies ran to.
SHADOW_MIN_CHARS = 400
SHADOW_MIN_RATIO = 0.6


def normalized_body(raw: str) -> str:
    """Frontmatter dropped, whitespace flattened - so reflow does not hide a copy."""
    return re.sub(r"\s+", " ", split_frontmatter(raw)[1]).strip()


def shadow_copies(mem_dir: str, on_disk: list[str], indexed: set[str],
                  names: dict[str, str]) -> list[dict]:
    """Un-indexed files whose body also sits inside a file that names them.

    This is the absorb defect. A group file takes the body, names the source so the
    reachability walk stays green, and the source stays on disk with no index line:
    two copies of one fact, and the copy that grep and semble hand a later session is
    the one nothing loads. Editing it is invisible. Indexed files are exempt - an
    index line makes the standalone reachable and unambiguous, which is the other
    accepted way to end an absorb.
    """
    raws = {name: scan(os.path.join(mem_dir, name)) for name in on_disk}
    bodies = {name: normalized_body(raw) for name, raw in raws.items()}

    out, claimed = [], set()
    for container in on_disk:
        haystack = bodies[container]
        for target, _ in sorted(refs_detailed(raws[container])):
            member = resolve(target, mem_dir, names)
            if member is None or member == container or member in indexed or member in claimed:
                continue
            body = bodies.get(member, "")
            if len(body) < SHADOW_MIN_CHARS:
                continue
            if body in haystack:
                ratio = 1.0
            else:
                # A near-copy: the absorbing session reworded a line or two. Compare
                # sentence-sized units so one edit does not clear the whole finding.
                units = [u for u in body.split(". ") if len(u) >= 40]
                if len(units) < 3:
                    continue
                ratio = sum(u in haystack for u in units) / len(units)
                if ratio < SHADOW_MIN_RATIO:
                    continue
            claimed.add(member)
            out.append({"file": member, "inside": container, "ratio": round(ratio, 2)})
    return out


def measure(mem_dir: str) -> dict:
    index_path = os.path.join(mem_dir, "MEMORY.md")
    if not os.path.isfile(index_path):
        return {"index": index_path, "exists": False}

    raw = scan(index_path)
    body = loaded_text(raw)
    lines = body.splitlines()
    n_lines = len(lines)
    n_bytes = len(body.encode("utf-8"))

    entries = []
    for line in lines:
        match = INDEX_LINK_RE.search(line)
        if not match:
            continue
        name = os.path.basename(match.group(1))
        target = os.path.join(mem_dir, name)
        kind, size = "", 0
        if os.path.isfile(target):
            content = scan(target)
            kind = frontmatter_field(content, "type") or "-"
            size = os.path.getsize(target)
        else:
            kind = "MISSING"
        entries.append({"file": name, "type": kind, "bytes": size, "line": line.strip()})

    on_disk = sorted(
        f for f in os.listdir(mem_dir)
        if f.endswith(".md") and f != "MEMORY.md" and os.path.isfile(os.path.join(mem_dir, f))
    )
    names = name_index(mem_dir)
    reached = reachable(mem_dir, body, names)
    indexed = {e["file"] for e in entries}
    return {
        "index": index_path,
        "exists": True,
        "lines": n_lines,
        "bytes": n_bytes,
        "line_pct": round(100 * n_lines / LINE_LIMIT),
        "byte_pct": round(100 * n_bytes / BYTE_LIMIT),
        "over": n_lines > LINE_LIMIT or n_bytes > BYTE_LIMIT,
        "near": n_lines > LINE_LIMIT * WARN_RATIO or n_bytes > BYTE_LIMIT * WARN_RATIO,
        "entries": entries,
        "on_disk": len(on_disk),
        "unreachable": [f for f in on_disk if f not in reached],
        "shadows": shadow_copies(mem_dir, on_disk, indexed, names),
        "dangling": dangling_refs(mem_dir, on_disk, names),
    }


def head(items: list, limit: int = 12) -> list:
    """Cap a printed list so a large memory dir cannot flood the caller's context."""
    if len(items) <= limit:
        return items
    shown = items[:limit]
    print(f"  (showing {limit} of {len(items)}; use --json for the rest)")
    return shown


def print_measure(mem_dir: str, how: str, data: dict) -> None:
    print(f"memory dir : {mem_dir}")
    print(f"resolved by: {how}")
    if not data.get("exists"):
        print("MEMORY.md  : absent - nothing to compact")
        return

    state = "OVER LIMIT" if data["over"] else ("near limit" if data["near"] else "ok")
    print(f"index      : {data['lines']} lines ({data['line_pct']}% of {LINE_LIMIT})"
          f" - {data['bytes']} bytes ({data['byte_pct']}% of {BYTE_LIMIT})  [{state}]")
    if data["over"]:
        print("             content past the first limit is dropped at session start")

    by_type: dict[str, list[dict]] = {}
    for entry in data["entries"]:
        by_type.setdefault(entry["type"], []).append(entry)
    print(f"entries    : {len(data['entries'])} indexed, {data['on_disk']} files on disk"
          + (f", {len(data['unreachable'])} unreachable" if data["unreachable"] else ", all reachable"))
    for kind in sorted(by_type):
        files = by_type[kind]
        print(f"  {kind:<9} {len(files):>3} files, {sum(f['bytes'] for f in files) / 1024:.0f}KB")

    if by_type.get("feedback"):
        print("\npromotion candidates (type: feedback - working guidance, usually project-independent).")
        print("bytes = what an unscoped rule would add to every session, so read before promoting:")
        for entry in head(sorted(by_type["feedback"], key=lambda e: -e["bytes"])):
            print(f"  {entry['bytes']:>6}B  {entry['file']}")
    for entry in data["entries"]:
        if entry["type"] == "MISSING":
            print(f"\nstale index line (file gone): {entry['file']}")
    if data["unreachable"]:
        print(f"\n{len(data['unreachable'])} files nothing can reach - not named by the index nor by"
              " any file the index leads to:")
        for name in head(data["unreachable"]):
            print(f"  {name}")

    if data.get("shadows"):
        print(f"\nSHADOW COPIES - {len(data['shadows'])} un-indexed files whose body is also inside"
              " the file that names them.")
        print("Two copies of one fact; the standalone is the one grep and semble hand a later"
              " session, and nothing loads it.")
        print("Close each one: delete the standalone, or give it its own MEMORY.md index line.")
        for item in head(data["shadows"]):
            print(f"  {item['file']}  ->  body {item['ratio']:.0%} inside {item['inside']}")

    if data.get("dangling"):
        print(f"\n{len(data['dangling'])} pointers land on nothing (both syntaxes checked;"
              " bare x.md is filtered to this store's own prefixes):")
        for item in head(data["dangling"]):
            form = f"[[{item['target'][:-3]}]]" if item["syntax"] == "wiki" else item["target"]
            print(f"  {item['source']}  ->  {form}")


# ---------------------------------------------------------------- instruction budget


def js_length(text: str) -> int:
    """String length as JS counts it: UTF-16 code units. Equal to len() inside the BMP."""
    return len(text.encode("utf-16-le")) // 2


EMPTY_SCALARS = {"", "[]", '""', "''", "~", "null"}


def has_paths_scope(raw: str) -> bool:
    """A rule with a non-empty `paths:` in its frontmatter loads only when a matching file is read.

    Frontmatter alone does not scope a rule - one with only `description:` still loads
    every session, so "starts with ---" is not the test. An empty `paths:` (bare, `[]`)
    counts as unscoped: whether Claude Code scopes it is unverified, and counting it
    overstates the budget rather than hiding a rule that may load everywhere.
    A leading BOM would otherwise stop the frontmatter from being recognised.
    """
    head, _ = split_frontmatter(raw.lstrip("\ufeff"))
    lines = head.splitlines()
    for i, line in enumerate(lines):
        match = re.match(r"paths\s*:(.*)$", line)
        if not match:
            continue
        if match.group(1).strip() not in EMPTY_SCALARS:
            return True
        # Block list: the item lines that follow, up to the next top-level key.
        for item in lines[i + 1:]:
            # "- " with a space: the closing "---" fence must not read as an item.
            listed = re.match(r"\s*-\s+(\S.*?)\s*$", item)
            if listed and listed.group(1) not in EMPTY_SCALARS:
                return True
            if item.strip() and not item.startswith((" ", "\t", "-")):
                break
        return False
    return False


def rule_files(rules_dir: str) -> list[str]:
    """Every *.md under rules_dir, recursively, following symlinked dirs without looping."""
    found, visited = [], set()
    for root, dirs, files in os.walk(rules_dir, followlinks=True):
        real = os.path.realpath(root)
        if real in visited:
            dirs[:] = []
            continue
        visited.add(real)
        dirs.sort()
        for name in sorted(files):
            path = os.path.join(root, name)
            if name.endswith(".md") and os.path.isfile(path):
                found.append(path)
    return found


def startup_rules(rules_dir: str) -> list[str]:
    """The rule files under rules_dir that load every session: no `paths:` scope."""
    return [path for path in rule_files(rules_dir) if not has_paths_scope(scan(path))]


def startup_instruction_files(project: str, home: str = HOME) -> list[str]:
    """Instruction files Claude Code loads at session start for a session opened in project.

    User level: ~/.claude/CLAUDE.md and unscoped ~/.claude/rules/**. Then every directory
    from project up to / contributes CLAUDE.md, CLAUDE.local.md, .claude/CLAUDE.md and
    unscoped .claude/rules/**. Deduplicated by real path, because walking up through home
    reaches ~/.claude a second time as an ancestor's .claude/.
    """
    candidates = [os.path.join(home, ".claude", "CLAUDE.md")]
    candidates += startup_rules(os.path.join(home, ".claude", "rules"))
    current = os.path.abspath(project)
    while True:
        for rel in ("CLAUDE.md", "CLAUDE.local.md", os.path.join(".claude", "CLAUDE.md")):
            candidates.append(os.path.join(current, rel))
        candidates += startup_rules(os.path.join(current, ".claude", "rules"))
        parent = os.path.dirname(current)
        if parent == current:
            break
        current = parent

    seen, out = set(), []
    for path in candidates:
        real = os.path.realpath(path)
        if real in seen or not os.path.isfile(path):
            continue
        seen.add(real)
        out.append(path)
    return out


def file_chars(path: str) -> int:
    # newline="" keeps \r\n as two chars, as a JS reader of the raw file sees it.
    with open(path, encoding="utf-8", errors="replace", newline="") as fh:
        return js_length(fh.read())


def budget_state(total: int) -> str:
    if total >= BUDGET_LIMIT:
        return "over"
    return "warn" if total >= BUDGET_WARN else "ok"


def instruction_budget(project: str, home: str = HOME) -> dict:
    files = [{"path": p, "chars": file_chars(p)} for p in startup_instruction_files(project, home)]
    total = sum(f["chars"] for f in files)
    return {"project": os.path.abspath(project), "files": files, "total": total,
            "limit": BUDGET_LIMIT, "state": budget_state(total)}


def print_budget(budget: dict) -> None:
    print(f"\ninstruction budget for {budget['project']} (startup files, MEMORY.md excluded):")
    for item in budget["files"]:
        print(f"  {item['chars']:>7}  {item['path']}")
    print(f"  {budget['total']:>7}  total of {BUDGET_LIMIT} ({round(100 * budget['total'] / BUDGET_LIMIT)}%)"
          f"  [{budget['state']}]")
    if budget["state"] == "over":
        print("           Claude Code warns at session start; trim CLAUDE.md or scope rules with paths:")


# ---------------------------------------------------------------- promoting


def rules_name(memory_file: str) -> str:
    stem = os.path.splitext(os.path.basename(memory_file))[0]
    for prefix in ("feedback_", "feedback-", "user_", "user-"):
        if stem.startswith(prefix):
            stem = stem[len(prefix):]
            break
    return stem.replace("_", "-") + ".md"


def strip_index_line(index_path: str, memory_file: str) -> bool:
    """Drop the index line that links to memory_file. Exact-string filter, no sed."""
    raw = read(index_path)
    kept, removed = [], False
    for line in raw.splitlines(keepends=True):
        match = INDEX_LINK_RE.search(line)
        if match and os.path.basename(match.group(1)) == memory_file:
            removed = True
            continue
        kept.append(line)
    if removed:
        with open(index_path, "w", encoding="utf-8") as fh:
            fh.write("".join(kept))
    return removed


def promote(mem_dir: str, memory_file: str, paths: list[str], dry_run: bool,
            project: str, home: str = HOME) -> int:
    # promote reads a file and then deletes it, so the target must be a bare name that
    # resolves inside mem_dir. os.path.join alone gives no containment: an absolute
    # argument discards mem_dir entirely, and ".." walks out of it.
    if memory_file != os.path.basename(memory_file) or memory_file in ("", ".", ".."):
        print(f"error: expected a bare filename in the memory dir, got {memory_file!r}", file=sys.stderr)
        return 1
    source = os.path.join(mem_dir, memory_file)
    if os.path.dirname(os.path.realpath(source)) != os.path.realpath(mem_dir):
        print(f"error: {memory_file} resolves outside {mem_dir}", file=sys.stderr)
        return 1
    if not os.path.isfile(source):
        print(f"error: {source} not found", file=sys.stderr)
        return 1

    try:
        raw = read(source)
    except UnicodeDecodeError as exc:
        print(f"error: {memory_file} is not valid UTF-8 ({exc}) - a rule loads every session,"
              " so fix the file before promoting it", file=sys.stderr)
        return 1
    _, body = split_frontmatter(raw)
    title = frontmatter_field(raw, "description") or os.path.splitext(memory_file)[0]
    body = body.strip()

    rules_dir = os.path.join(home, ".claude", "rules")
    target = os.path.join(rules_dir, rules_name(memory_file))
    if os.path.exists(target):
        print(f"error: {target} already exists - merge by hand or pick another name", file=sys.stderr)
        return 1

    parts = []
    if paths:
        parts.append("---\npaths:\n" + "".join(f'  - "{p}"\n' for p in paths) + "---\n\n")
    if not body.lstrip().startswith("#"):
        parts.append(f"# {title}\n\n")
    parts.append(body + "\n")
    content = "".join(parts)

    scope = f"scoped to {', '.join(paths)}" if paths else "loaded every session (no paths scope)"
    print(f"{memory_file}  ->  {target}")
    print(f"  {scope}")
    print(f"  {len(content.encode('utf-8'))} bytes")

    # A paths-scoped rule does not load at startup, so only an unscoped one adds to the
    # budget. Checked before any write, and on --dry-run too, so the preview tells the truth.
    total = instruction_budget(project, home)["total"]
    added = 0 if paths else js_length(content)
    print(f"  instruction budget: {total} + {added} = {total + added} chars (promote ceiling {PROMOTE_CEILING})")
    if added and total + added > PROMOTE_CEILING:
        print(f"error: promoting {memory_file} unscoped would put the startup instruction files at"
              f" {total + added} chars, over the {PROMOTE_CEILING} promote ceiling (current total"
              f" {total}). Scope it with --paths, or trim CLAUDE.md / rules first.", file=sys.stderr)
        return 1
    if dry_run:
        print("  dry run - nothing written")
        return 0

    os.makedirs(rules_dir, exist_ok=True)
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(content)
    os.remove(source)
    try:
        removed = strip_index_line(os.path.join(mem_dir, "MEMORY.md"), memory_file)
        note = "dropped" if removed else "not in MEMORY.md - a group file may name it instead"
    except UnicodeDecodeError:
        note = "left in place - MEMORY.md is not valid UTF-8, edit it by hand"
    print(f"  written, source removed, index line {note}")

    linkers = [
        f for f in os.listdir(mem_dir)
        if f.endswith(".md") and memory_file in refs(scan(os.path.join(mem_dir, f)))
    ]
    if linkers:
        print(f"  references to {memory_file} now dangle in: {', '.join(linkers)}")
    outbound = sorted(refs(body) - {memory_file})
    if outbound:
        print(f"  the rule still names memory files: {', '.join(outbound)}")
        print("  rules cannot resolve them - inline what matters or drop the reference")
    return 0


# ---------------------------------------------------------------- selftest

# Every case here is a bug this tool shipped with at least once. refs() decides what counts
# as reachable, and a miss there reports a live file as an orphan the caller may then delete.
SELFTEST_CASES = [
    ("see bare_mention.md.", {"bare_mention.md"}),
    ("see bare_mention.md, then", {"bare_mention.md"}),
    ("backup lives at index.md.bak", set()),
    ("[[plain]] and [[with_ext.md]]", {"plain.md", "with_ext.md"}),
    ("[[target#Heading]] and [[other|Alias]]", {"target.md", "other.md"}),
    ("inline `hidden.md` stays inert", set()),
    ("fenced:\n```\nrm fenced.md\n```\n", set()),
    ("path/to/nested.md", {"nested.md"}),
    ("a.md and b.md", {"a.md", "b.md"}),
    ("unclosed [[foo\nbut real.md is still seen ]] here", {"real.md"}),
]


# refs_detailed() also has to say WHICH syntax found each target, because the dangling
# report tells the caller what to repair and the two are fixed differently.
SYNTAX_CASES = [
    ("[[wiki_one]] and bare_two.md", {("wiki_one.md", "wiki"), ("bare_two.md", "bare")}),
    ("[[wiki_three.md]]", {("wiki_three.md", "wiki")}),
]


def build_store(tmp: str, files: dict[str, str]) -> None:
    for name, text in files.items():
        with open(os.path.join(tmp, name), "w", encoding="utf-8") as fh:
            fh.write(text)


def check(label: str, got, want) -> int:
    if got == want:
        print(f"  ok    {label}")
        return 0
    print(f"  FAIL  {label}\n        got {got!r}\n        want {want!r}")
    return 1


def selftest() -> int:
    failed = 0
    for text, want in SELFTEST_CASES:
        got = refs(text)
        if got == want:
            print(f"  ok    {text!r}")
            continue
        failed += 1
        print(f"  FAIL  {text!r}\n        got {sorted(got)}, want {sorted(want)}")
    for text, want in SYNTAX_CASES:
        failed += check(f"refs_detailed {text!r}", refs_detailed(text), want)

    # reachable() walks the filesystem, so it needs a throwaway tree: a two-level group
    # index, a reference cycle, a reference to a file that does not exist, and an orphan.
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        files = {
            "MEMORY.md": "- [Group](group.md) - merged\n- [Cycle](cycle_a.md) - loops\n",
            "group.md": "member_one.md and [[member_two]] and gone_missing.md\n",
            "member_one.md": "one\n",
            "member_two.md": "two\n",
            "cycle_a.md": "back to cycle_b.md\n",
            "cycle_b.md": "back to cycle_a.md\n",
            "orphan.md": "nobody names me\n",
        }
        build_store(tmp, files)
        got = reachable(tmp, files["MEMORY.md"])
        want = {"group.md", "member_one.md", "member_two.md", "gone_missing.md",
                "cycle_a.md", "cycle_b.md"}
        if got == want:
            print("  ok    reachable(): group indirection, cycle, missing target")
        else:
            failed += 1
            print(f"  FAIL  reachable()\n        got {sorted(got)}, want {sorted(want)}")

    # A store shaped like the one that produced 53 shadows: a link that only resolves
    # through `name:`, a body absorbed into a group file with the source left behind,
    # the same absorption done correctly (source still indexed), and a dead pointer in
    # each syntax next to a repo-doc mention that must not be reported.
    body = ("The absorbed fact runs several sentences so it clears the size floor. "
            "It states a measured thing, then the consequence of that thing. "
            "It names the file that has to change and the check that proves it changed. "
            "It records what was ruled out, so a later session does not re-investigate. "
            "It closes with the invariant a later session has to keep. "
            "None of it is short enough to land inside a group file by accident. ")
    assert len(body) > SHADOW_MIN_CHARS, "fixture must clear the size floor it is testing"
    # 3 of the 53 observed shadows were not exact substrings - the absorbing session
    # reworded a sentence. Keep five of these six and paraphrase the last.
    sentences = [
        "The reworded fact keeps most of its sentences through the absorption step",
        "It names the measurement that settled the open question at the time it ran",
        "It carries forward the consequence that a later session still has to act on",
        "It records the option that was ruled out, together with the reason it was",
        "It states which file owns the behavior so nobody re-derives that ownership",
        "It ends with one sentence the group file chose to paraphrase instead of copy",
    ]
    reworded = ". ".join(sentences) + "."
    assert len(reworded) > SHADOW_MIN_CHARS, "fixture must clear the size floor it is testing"
    with tempfile.TemporaryDirectory() as tmp:
        files = {
            "MEMORY.md": ("- [Things](group_things.md) - merged\n"
                          "- [Kept](reference_kept.md) - has its own line\n"),
            "group_things.md": (
                "---\nname: group-things\n---\n"
                f"reference_absorbed.md: {body}\n"
                f"reference_kept.md: {body}\n"
                "reference_stub.md: too short to be a copy.\n"
                f"reference_reworded.md: {'. '.join(sentences[:5])}. Then a paraphrase.\n"
                "[[renamed-entry]] survived the rename.\n"
                "reference_deleted_sibling.md was removed.\n"
                "[[ghost-entry]] never existed.\n"
                "see deploy-notes.md in the repo\n"
            ),
            "reference_absorbed.md": f"---\nname: reference_absorbed\n---\n{body}\n",
            "reference_kept.md": f"---\nname: reference_kept\n---\n{body}\n",
            "reference_renamed_file.md": "---\nname: renamed-entry\n---\nstill here\n",
            # Below the size floor: a one-liner can sit inside a group file without being
            # a copy, and flagging it would make the gate noisy enough to be ignored.
            "reference_stub.md": "---\nname: reference_stub\n---\ntoo short to be a copy.\n",
            "reference_reworded.md": f"---\nname: reference_reworded\n---\n{reworded}\n",
        }
        build_store(tmp, files)
        data = measure(tmp)

        failed += check("name: resolution keeps a renamed target off the orphan list",
                        data["unreachable"], [])
        failed += check("shadow_copies(): verbatim and reworded flagged; indexed and stub are not",
                        [(s["file"], s["inside"], s["ratio"]) for s in data["shadows"]],
                        [("reference_absorbed.md", "group_things.md", 1.0),
                         ("reference_reworded.md", "group_things.md", 0.83)])
        failed += check("dangling_refs(): both syntaxes, repo doc filtered out",
                        sorted((d["target"], d["syntax"]) for d in data["dangling"]),
                        [("ghost-entry.md", "wiki"), ("reference_deleted_sibling.md", "bare")])

        def gate() -> int:
            """verify's exit code - the only thing that makes a shadow cost anything."""
            return subprocess.run(
                [sys.executable, os.path.abspath(__file__), "--dir", tmp, "verify"],
                capture_output=True, text=True).returncode

        failed += check("verify exits non-zero while a shadow copy is on disk", gate(), 1)

        # Ablation: the shadow finding must come from the duplicate body, not from the
        # file merely being un-indexed - 341 of this store's files are un-indexed on purpose.
        build_store(tmp, {
            "reference_absorbed.md": "---\nname: reference_absorbed\n---\nA different fact entirely.\n",
            "reference_reworded.md": "---\nname: reference_reworded\n---\nAlso a different fact.\n",
        })
        failed += check("no shadow when the standalone body is not a copy",
                        measure(tmp)["shadows"], [])
        failed += check("verify exits 0 once the shadows are gone", gate(), 0)

    # The instruction budget: what loads at startup, from a fake home and a project two
    # levels below an ancestor. Never the real ~/.claude - home is a parameter for this.
    failed += check("js_length counts UTF-16 units, as the warning does", js_length("a\U0001F600"), 3)
    with tempfile.TemporaryDirectory() as tmp:
        home = os.path.join(tmp, "home")
        project = os.path.join(tmp, "root", "proj")
        tree = {
            os.path.join(home, ".claude", "CLAUDE.md"): "user\n",
            os.path.join(home, ".claude", "rules", "scoped.md"): "---\npaths:\n  - \"src/**\"\n---\nscoped\n",
            os.path.join(home, ".claude", "rules", "sub", "described.md"): "---\ndescription: d\n---\nalways\n",
            os.path.join(tmp, "root", "CLAUDE.local.md"): "ancestor local\n",
            os.path.join(project, "CLAUDE.md"): "project\n",
        }
        for path, text in tree.items():
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
        counted = {os.path.relpath(p, tmp) for p in startup_instruction_files(project, home)
                   if os.path.realpath(p).startswith(os.path.realpath(tmp) + os.sep)}
        failed += check("rule with paths: frontmatter is excluded",
                        os.path.join("home", ".claude", "rules", "scoped.md") in counted, False)
        failed += check("rule with frontmatter but no paths: is counted (nested dir)",
                        os.path.join("home", ".claude", "rules", "sub", "described.md") in counted, True)
        failed += check("ancestor CLAUDE.local.md is counted",
                        os.path.join("root", "CLAUDE.local.md") in counted, True)

        # promote: a fake rules dir already near the ceiling, one feedback entry to move.
        mem = os.path.join(tmp, "mem")
        os.makedirs(mem)
        build_store(mem, {
            "MEMORY.md": "- [Rule](feedback_big.md) - guidance\n",
            "feedback_big.md": "---\nname: feedback_big\ndescription: big\n---\n" + "guidance " * 20 + "\n",
        })
        filler = os.path.join(home, ".claude", "rules", "filler.md")
        with open(filler, "w", encoding="utf-8") as fh:
            fh.write("x" * (PROMOTE_CEILING - instruction_budget(project, home)["total"] - 50))
        promoted = os.path.join(home, ".claude", "rules", "big.md")
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            refused = promote(mem, "feedback_big.md", [], False, project, home)
        failed += check("promote refuses an unscoped rule past the ceiling, writing nothing",
                        (refused, os.path.exists(promoted), os.path.exists(os.path.join(mem, "feedback_big.md"))),
                        (1, False, True))
        # A paths-scoped rule never loads at startup, so the ceiling does not apply to it.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            scoped = promote(mem, "feedback_big.md", ["src/**"], False, project, home)
        failed += check("promote still allows a paths-scoped rule over the ceiling",
                        (scoped, os.path.exists(promoted)), (0, True))

    # Second budget fixture: the project sits UNDER home, the real layout, so the ancestor
    # walk reaches ~/.claude a second time. Plus a symlinked rules dir with a loop, empty
    # `paths:` values, and a BOM ahead of the frontmatter.
    with tempfile.TemporaryDirectory() as tmp:
        home = os.path.join(tmp, "home")
        rules = os.path.join(home, ".claude", "rules")
        project = os.path.join(home, "work", "proj")
        elsewhere = os.path.join(tmp, "elsewhere")
        tree = {
            os.path.join(home, ".claude", "CLAUDE.md"): "user\n",
            os.path.join(rules, "plain.md"): "plain\n",
            os.path.join(rules, "empty_list.md"): "---\npaths: []\n---\nempty list\n",
            os.path.join(rules, "bare.md"): "---\npaths:\n---\nbare key\n",
            os.path.join(rules, "scalar.md"): "---\npaths: src/**\n---\nscalar\n",
            os.path.join(rules, "bom.md"): "\ufeff---\npaths:\n  - \"x/**\"\n---\nbom\n",
            os.path.join(elsewhere, "shared.md"): "shared\n",
            os.path.join(project, "CLAUDE.md"): "project\n",
        }
        for path, text in tree.items():
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
        os.symlink(elsewhere, os.path.join(rules, "linked"))
        os.symlink(elsewhere, os.path.join(elsewhere, "loop"))  # a cycle the walk must survive

        files = startup_instruction_files(project, home)
        reals = [os.path.realpath(p) for p in files]
        failed += check("project under home: ~/.claude/CLAUDE.md counted once (realpath dedup)",
                        reals.count(os.path.realpath(os.path.join(home, ".claude", "CLAUDE.md"))), 1)
        shared = os.path.realpath(os.path.join(elsewhere, "shared.md"))
        failed += check("rule inside a symlinked rules dir is counted", shared in reals, True)
        failed += check("symlink loop: walk ends, the looped file is listed once",
                        [os.path.realpath(p) for p in rule_files(rules)].count(shared), 1)
        names = {os.path.basename(p) for p in files}
        failed += check("empty paths: ([] and bare key) is counted, not treated as scoped",
                        ("empty_list.md" in names, "bare.md" in names), (True, True))
        failed += check("scalar paths: value is still scoped", "scalar.md" in names, False)
        failed += check("BOM before frontmatter: a paths-scoped rule stays excluded", "bom.md" in names, False)

    total = len(SELFTEST_CASES) + len(SYNTAX_CASES) + 19
    print(f"{total - failed}/{total} passed")
    return 1 if failed else 0


# ---------------------------------------------------------------- entry


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", help="memory directory (default: resolve from cwd)")
    parser.add_argument("--project", help="directory a session opens in, for the instruction"
                        " budget (default: cwd)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_measure = sub.add_parser("measure", help="report index size and promotion candidates")
    p_measure.add_argument("--json", action="store_true")

    p_promote = sub.add_parser("promote", help="move a memory file into ~/.claude/rules/")
    p_promote.add_argument("file", help="memory filename, e.g. feedback_try_before_asking.md")
    p_promote.add_argument("--paths", default="", help="comma-separated globs for the rule's paths frontmatter")
    p_promote.add_argument("--dry-run", action="store_true")

    sub.add_parser("verify", help="re-measure and list ~/.claude/rules/")
    sub.add_parser("selftest", help="check reference parsing against its known-bug cases")

    args = parser.parse_args()
    if args.cmd == "selftest":
        return selftest()

    cwd = os.getcwd()
    mem_dir, how = (os.path.expanduser(args.dir), "--dir") if args.dir else memory_dir(cwd)
    # Claude Code walks instruction files up from the directory the session opens in, so
    # cwd is the default. The memory slug cannot be mapped back to a path (it is lossy).
    project = os.path.abspath(os.path.expanduser(args.project)) if args.project else cwd

    if args.cmd == "measure":
        data = measure(mem_dir)
        budget = instruction_budget(project)
        if args.json:
            print(json.dumps({"dir": mem_dir, "resolved_by": how, **data, "instruction_budget": budget},
                             ensure_ascii=False, indent=1))
        else:
            print_measure(mem_dir, how, data)
            print_budget(budget)
        return 0

    if args.cmd == "promote":
        paths = [p.strip() for p in args.paths.split(",") if p.strip()]
        return promote(mem_dir, args.file, paths, args.dry_run, project)

    data = measure(mem_dir)
    print_measure(mem_dir, how, data)
    print_budget(instruction_budget(project))
    print()
    # verify is the gate a compaction run has to pass, so a surviving shadow copy has to
    # cost something. Printing it next to an otherwise-green report is how 53 of them
    # accumulated: the walk said "all reachable" and the operator read that as done.
    failed = bool(data.get("shadows"))
    if os.path.isdir(RULES_DIR):
        # The same recursive walk and the same always-loaded set the budget counts, so
        # this listing and the budget block above it cannot disagree.
        rules = rule_files(RULES_DIR)
        always = set(startup_rules(RULES_DIR))
        print(f"{RULES_DIR}: {len(rules)} rules, {len(always)} loaded every session")
        for path in rules:
            scope = "always" if path in always else "paths-scoped"
            print(f"  {os.path.getsize(path):>6}B  {scope:<12} {os.path.relpath(path, RULES_DIR)}")
    else:
        print(f"{RULES_DIR}: does not exist yet")
    if failed:
        print(f"\nverify FAILED: {len(data['shadows'])} shadow copies still on disk")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
