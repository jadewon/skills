#!/usr/bin/env python3
"""Article HTML -> Markdown converter (Python stdlib only, no deps).

Usage:  python3 html2md.py <file.html> > out.md

Keeps only article content (headings, paragraphs, lists, figures, quotes,
code) and drops chrome: svg, buttons, form controls, scripts, styles.
Tuned for browser-saved article pages (Medium, tech blogs) where class names
are minified and unusable as selectors.
"""
import html
import re
import sys
from html.parser import HTMLParser

BLOCKS = {"h1", "h2", "h3", "h4", "p", "li", "figcaption", "blockquote", "pre"}
SKIP = {"svg", "button", "input", "label", "select", "textarea",
        "style", "script", "noscript", "nav", "footer", "form"}
# Void elements have no end tag -- they must never open a skip/nesting depth,
# otherwise the counter never unwinds and the rest of the document is dropped.
VOID = {"img", "br", "hr", "input", "meta", "link", "source",
        "area", "base", "col", "embed", "param", "track", "wbr"}
# Non-article UI text that survives the tag filter (Medium subscribe widget).
BOILERPLATE = (
    "stories in your inbox",
    "Join Medium for free",
)
PREFIX = {
    "h1": "# ", "h2": "## ", "h3": "### ", "h4": "#### ",
    "li": "- ", "blockquote": "> ", "p": "", "pre": "", "figcaption": "",
}
# Images declaring a dimension below this are avatars/icons, not article figures.
ICON_MAX_PX = 100
DIM_IN_URL = re.compile(r"(?:fill|fit|resize)[:/](\d+)[:x](\d+)")


def is_icon(src, attrs):
    """True for byline avatars / UI icons, which should not survive conversion."""
    w, h = attrs.get("width", ""), attrs.get("height", "")
    if w.isdigit() and h.isdigit():
        return max(int(w), int(h)) < ICON_MAX_PX
    m = DIM_IN_URL.search(src)
    return bool(m) and max(int(m.group(1)), int(m.group(2))) < ICON_MAX_PX


class ArticleParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out = []
        self.buf = []
        self.block = None
        self.skip_depth = 0
        self.href = None
        self.link_buf = None
        self.in_figure = False
        self.figure_imgs = []
        self.doc_title = None
        self.in_title = False

    # --- helpers -------------------------------------------------
    def emit(self, text, raw=False):
        if not raw:
            # Medium glues trailing words together with nbsp -> normalize.
            text = re.sub(r"[ \t\xa0]+", " ", text).strip()
        if text and not any(pat in text for pat in BOILERPLATE):
            self.out.append(text)

    def flush(self):
        if self.block is None:
            return
        block, text = self.block, "".join(self.buf).strip()
        self.buf, self.block = [], None
        if not text:
            return
        if block == "pre":
            self.emit(f"```\n{text}\n```", raw=True)  # keep indentation intact
        elif block == "figcaption":
            self.emit(f"*{text}*")  # caption renders italic, not as a block
        else:
            self.emit(PREFIX.get(block, "") + text)

    def add(self, text):
        if self.link_buf is not None:
            self.link_buf.append(text)
        elif self.block is not None:
            self.buf.append(text)

    def emit_image(self, src, alt, attrs):
        if not src or src.startswith("data:") or is_icon(src, attrs):
            return
        md = f"![{alt}]({src})"
        if self.in_figure:
            self.figure_imgs.append(md)  # emitted after its caption
        else:
            self.flush()
            self.emit(md)

    # --- handlers ------------------------------------------------
    def handle_starttag(self, tag, attrs):
        a = dict(attrs)
        if self.skip_depth:
            if tag not in VOID:
                self.skip_depth += 1
            return
        if tag in SKIP:
            if tag not in VOID:
                self.skip_depth = 1
            return
        if tag == "figure":
            self.in_figure, self.figure_imgs = True, []
        elif tag == "img":
            self.emit_image(a.get("src", ""), a.get("alt", "").strip(), a)
        elif tag == "br":
            self.add("  \n")
        elif tag == "a":
            self.href, self.link_buf = a.get("href"), []
        elif tag in ("em", "i"):
            self.add("*")
        elif tag in ("strong", "b"):
            self.add("**")
        elif tag == "code":
            if self.block != "pre":  # inside <pre> the fence already marks it
                self.add("`")
        elif tag == "title":
            self.in_title = True
        elif tag in BLOCKS:
            self.flush()
            self.block = tag

    def handle_endtag(self, tag):
        if self.skip_depth:
            # Mirror handle_starttag's VOID guard: a self-closed void tag inside
            # a skip region (e.g. <input/> in a <form>) fires a synthetic end
            # tag that must not unwind the depth the void start didn't open.
            if tag not in VOID:
                self.skip_depth -= 1
            return
        if tag == "figure":
            self.flush()
            for img in self.figure_imgs:
                self.emit(img)
            self.in_figure, self.figure_imgs = False, []
        elif tag == "a":
            text = "".join(self.link_buf or []).strip()
            self.link_buf = None
            if text:
                self.add(f"[{text}]({self.href})" if self.href else text)
            self.href = None
        elif tag in ("em", "i"):
            self.add("*")
        elif tag in ("strong", "b"):
            self.add("**")
        elif tag == "code":
            if self.block != "pre":  # inside <pre> the fence already marks it
                self.add("`")
        elif tag == "title":
            self.in_title = False
        elif tag in BLOCKS:
            self.flush()

    def handle_data(self, data):
        if self.skip_depth:
            return
        if self.in_title:
            self.doc_title = (self.doc_title or "") + data
        else:
            self.add(data)


def convert(path):
    raw = open(path, encoding="utf-8", errors="replace").read()
    topics = re.findall(r'aria-label="Topic: ([^"]+)"', raw)

    p = ArticleParser()
    p.feed(raw)
    p.flush()

    lines = p.out
    title_idx = next((i for i, l in enumerate(lines) if l.startswith("# ")), None)
    if title_idx is not None:
        title = lines[title_idx][2:]
    else:
        title = (p.doc_title or "").strip() or "Untitled"

    head = [f"# {title}"]
    if topics:
        head.append("**Topics:** "
                    + ", ".join(html.unescape(t) for t in dict.fromkeys(topics)))
    # Drop only the one line picked as the title, not every "# "-prefixed line --
    # a second <h1> in the body is real content, not a duplicate title.
    body = [l for i, l in enumerate(lines) if i != title_idx]

    # Blocks are blank-line separated, except adjacent list items (tight list).
    doc = ""
    for line in head + body:
        if doc:
            doc += "\n" if line.startswith("- ") and prev.startswith("- ") else "\n\n"
        doc, prev = doc + line, line
    return doc + "\n"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: html2md.py <file.html>")
    sys.stdout.write(convert(sys.argv[1]))
