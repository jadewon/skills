---
name: html2md
description: Convert a saved HTML article/page into clean Markdown (headings, paragraphs, lists, links, figures, code) with site chrome stripped. Use for "HTML을 md로 뽑아줘", "이 페이지 markdown 으로 변환", "html to markdown", or when handed a .html file to read/summarize.
disable-model-invocation: false
argument-hint: "<file.html> [output.md] — e.g. /html2md ~/Downloads/article.html"
allowed-tools: Bash, Read, Write
---

# html2md

Python-stdlib converter for browser-saved article pages. No pandoc, no pip install.

```bash
python3 "${CLAUDE_SKILL_DIR}/html2md.py" <input.html> > <output.md>
```

Output path: if the user gave one, use it. Otherwise write next to the input with the
`.md` extension (`/tmp/airbnb.html` → `/tmp/airbnb.md`). Convert first, then read the
result — do not read the raw HTML into context, that is what this skill exists to avoid.

## What it produces

| Source | Markdown |
|---|---|
| `h1`–`h4` | `#`–`####` |
| `p`, `li`, `blockquote` | paragraph, `- ` item (tight list), `> ` quote |
| `a`, `em`/`i`, `strong`/`b`, `code` | `[text](href)`, `*x*`, `**x**`, `` `x` `` |
| `pre` | fenced block, indentation preserved |
| `figure` + `figcaption` | italic caption line, then `![alt](src)` |
| `aria-label="Topic: X"` (Medium) | `**Topics:**` line under the title |

Title comes from the first `h1`; falls back to `<title>`, then `Untitled`.

Dropped: `svg`, `button`, `input`, `label`, `select`, `textarea`, `script`, `style`,
`nav`, `footer`, `form`; `data:` URIs; images under 100px (byline avatars, icons);
Medium's "stories in your inbox" subscribe widget.

Not escaped: a literal `_`, `` ` `` or `*` in the source text renders as-is in the
output, which markdown viewers may interpret as emphasis or code.

## Extending

Three lists at the top of `html2md.py` are the tuning surface — edit them rather than
the parser: `SKIP` (tags to drop whole), `BOILERPLATE` (non-article UI text that
survives the tag filter), `ICON_MAX_PX` (avatar cutoff).

`VOID` is not a tuning knob: void elements must stay listed there or the skip counter
never unwinds and everything after the first `<input>` is silently dropped.
