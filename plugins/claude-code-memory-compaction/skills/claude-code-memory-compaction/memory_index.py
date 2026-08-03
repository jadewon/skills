#!/usr/bin/env python3
"""memory_index.py - measure a Claude Code auto-memory index and promote entries to ~/.claude/rules/.

Subcommands:
  measure   report MEMORY.md load size against the 200-line / 25KB startup limits
  promote   move one memory file into ~/.claude/rules/ and drop its index line
  verify    re-measure and list rules files

Only the portion of MEMORY.md that Claude Code actually loads is measured: YAML
frontmatter and block-level HTML comments are stripped before the limit check
(Claude Code >= 2.1.211), so counting the raw file overstates the size.

Python stdlib only.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

LINE_LIMIT = 200
BYTE_LIMIT = 25 * 1024
WARN_RATIO = 0.8

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
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def measure(mem_dir: str) -> dict:
    index_path = os.path.join(mem_dir, "MEMORY.md")
    if not os.path.isfile(index_path):
        return {"index": index_path, "exists": False}

    raw = read(index_path)
    body = loaded_text(raw)
    lines = body.splitlines()
    n_lines = len(lines)
    n_bytes = len(body.encode("utf-8"))

    listed: set[str] = set()
    entries = []
    for line in lines:
        match = INDEX_LINK_RE.search(line)
        if not match:
            continue
        name = os.path.basename(match.group(1))
        listed.add(name)
        target = os.path.join(mem_dir, name)
        kind, size = "", 0
        if os.path.isfile(target):
            content = read(target)
            kind = frontmatter_field(content, "type") or "-"
            size = os.path.getsize(target)
        else:
            kind = "MISSING"
        entries.append({"file": name, "type": kind, "bytes": size, "line": line.strip()})

    on_disk = sorted(
        f for f in os.listdir(mem_dir)
        if f.endswith(".md") and f != "MEMORY.md" and os.path.isfile(os.path.join(mem_dir, f))
    )
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
        "unlisted": [f for f in on_disk if f not in listed],
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
    print(f"entries    : {len(data['entries'])} indexed"
          + (f", {len(data['unlisted'])} on disk but unlisted" if data["unlisted"] else ""))
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
    if data["unlisted"]:
        print(f"\n{len(data['unlisted'])} files on disk have no index line - they never load and"
              " nothing points at them:")
        for name in head(data["unlisted"]):
            print(f"  {name}")


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


def promote(mem_dir: str, memory_file: str, paths: list[str], dry_run: bool) -> int:
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

    raw = read(source)
    _, body = split_frontmatter(raw)
    title = frontmatter_field(raw, "description") or os.path.splitext(memory_file)[0]
    body = body.strip()

    target = os.path.join(RULES_DIR, rules_name(memory_file))
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
    if dry_run:
        print("  dry run - nothing written")
        return 0

    os.makedirs(RULES_DIR, exist_ok=True)
    with open(target, "w", encoding="utf-8") as fh:
        fh.write(content)
    os.remove(source)
    removed = strip_index_line(os.path.join(mem_dir, "MEMORY.md"), memory_file)
    print(f"  written, source removed, index line {'dropped' if removed else 'NOT FOUND - check MEMORY.md'}")

    stem = os.path.splitext(memory_file)[0]
    linkers = [
        f for f in os.listdir(mem_dir)
        if f.endswith(".md") and f"[[{stem}]]" in read(os.path.join(mem_dir, f))
    ]
    if linkers:
        print(f"  inbound [[{stem}]] links now dangle in: {', '.join(linkers)}")
    outbound = sorted(set(re.findall(r"\[\[([^\]]+)\]\]", body)))
    if outbound:
        print(f"  outbound links left in the rule point at memory files: {', '.join(outbound)}")
        print("  rules cannot resolve [[...]] - inline what matters or drop the link")
    return 0


# ---------------------------------------------------------------- entry


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dir", help="memory directory (default: resolve from cwd)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_measure = sub.add_parser("measure", help="report index size and promotion candidates")
    p_measure.add_argument("--json", action="store_true")

    p_promote = sub.add_parser("promote", help="move a memory file into ~/.claude/rules/")
    p_promote.add_argument("file", help="memory filename, e.g. feedback_try_before_asking.md")
    p_promote.add_argument("--paths", default="", help="comma-separated globs for the rule's paths frontmatter")
    p_promote.add_argument("--dry-run", action="store_true")

    sub.add_parser("verify", help="re-measure and list ~/.claude/rules/")

    args = parser.parse_args()
    cwd = os.getcwd()
    mem_dir, how = (os.path.expanduser(args.dir), "--dir") if args.dir else memory_dir(cwd)

    if args.cmd == "measure":
        data = measure(mem_dir)
        if args.json:
            print(json.dumps({"dir": mem_dir, "resolved_by": how, **data}, ensure_ascii=False, indent=1))
        else:
            print_measure(mem_dir, how, data)
        return 0

    if args.cmd == "promote":
        paths = [p.strip() for p in args.paths.split(",") if p.strip()]
        return promote(mem_dir, args.file, paths, args.dry_run)

    data = measure(mem_dir)
    print_measure(mem_dir, how, data)
    print()
    if os.path.isdir(RULES_DIR):
        rules = sorted(f for f in os.listdir(RULES_DIR) if f.endswith(".md"))
        always = [f for f in rules if not read(os.path.join(RULES_DIR, f)).lstrip().startswith("---")]
        print(f"{RULES_DIR}: {len(rules)} rules, {len(always)} loaded every session")
        for name in rules:
            raw = read(os.path.join(RULES_DIR, name))
            scope = "always" if not raw.lstrip().startswith("---") else "paths-scoped"
            print(f"  {len(raw.encode('utf-8')):>6}B  {scope:<12} {name}")
    else:
        print(f"{RULES_DIR}: does not exist yet")
    return 0


if __name__ == "__main__":
    sys.exit(main())
