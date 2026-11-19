#!/usr/bin/env python3
"""Static regression checks for the marketing site in website/.

Stdlib only, no network. Run from anywhere:

    python3 script/check_website.py

Exits non-zero if any check fails. Covers the things that have broken (or
could silently break) the site: missing assets, stale cache-busting stamps,
invalid JSON-LD, social preview image, SEO files, the Cloudflare Pages
_headers CSP vs. the scripts the page actually loads, the custom 404 page and
the privacy notice vs. third-party scripts.
"""
from __future__ import annotations

import hashlib
import json
import re
import struct
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlparse

SITE = Path(__file__).resolve().parent.parent / "website"
ORIGIN = "https://mackitty.com"

failures: list[str] = []
passes = 0


def check(cond: bool, msg: str) -> None:
    global passes
    if cond:
        passes += 1
        print(f"  [PASS] {msg}")
    else:
        failures.append(msg)
        print(f"  [FAIL] {msg}")


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.meta: dict[str, str] = {}
        self.links: list[dict[str, str]] = []
        self.refs: list[str] = []
        self.scripts: list[dict[str, str]] = []
        self.jsonld: list[str] = []
        self.h1 = 0
        self.title = ""
        self._in_title = False
        self._in_jsonld = False
        self._buf = ""
        self.text_by_id: dict[str, str] = {}
        self._capture_id: str | None = None
        self._capture_depth = 0

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if self._capture_id is not None:
            self._capture_depth += 1
        elif tag == "dialog" and a.get("id"):
            self._capture_id = a["id"]
            self._capture_depth = 1
            self.text_by_id[a["id"]] = ""
        if tag == "meta":
            key = a.get("property") or a.get("name")
            if key:
                self.meta[key] = a.get("content", "")
        elif tag == "link":
            self.links.append(a)
        elif tag == "title":
            self._in_title = True
        elif tag == "h1":
            self.h1 += 1
        elif tag == "script":
            self.scripts.append(a)
            if a.get("type") == "application/ld+json":
                self._in_jsonld = True
                self._buf = ""
        for attr in ("src", "href", "poster", "data-src"):
            if attr in a and not (tag == "a" and attr == "href"):
                self.refs.append(a[attr])

    def handle_endtag(self, tag):
        if self._capture_id is not None:
            self._capture_depth -= 1
            if self._capture_depth == 0:
                self._capture_id = None
        if tag == "title":
            self._in_title = False
        elif tag == "script" and self._in_jsonld:
            self.jsonld.append(self._buf)
            self._in_jsonld = False

    def handle_data(self, data):
        if self._in_title:
            self.title += data
        if self._in_jsonld:
            self._buf += data
        if self._capture_id is not None:
            self.text_by_id[self._capture_id] += data


def parse(path: Path) -> Page:
    p = Page()
    p.feed(path.read_text(encoding="utf-8"))
    return p


def image_size(path: Path) -> tuple[int, int] | None:
    data = path.read_bytes()
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            marker = data[i + 1]
            if marker in (0xC0, 0xC1, 0xC2):
                h, w = struct.unpack(">HH", data[i + 5 : i + 9])
                return w, h
            seg = struct.unpack(">H", data[i + 2 : i + 4])[0]
            i += 2 + seg
    return None


def local_path(ref: str) -> Path | None:
    u = urlparse(ref)
    if u.scheme in ("http", "https"):
        if f"{u.scheme}://{u.netloc}" != ORIGIN:
            return None
        ref = u.path
    elif u.scheme or ref.startswith("#") or ref.startswith("mailto:"):
        return None
    path = urlparse(ref).path.lstrip("/")
    return SITE / (path or "index.html")


def csp_directives(headers_text: str) -> dict[str, list[str]]:
    m = re.search(r"Content-Security-Policy:\s*(.+)", headers_text)
    if not m:
        return {}
    out = {}
    for part in m.group(1).split(";"):
        bits = part.split()
        if bits:
            out[bits[0]] = bits[1:]
    return out


def main() -> int:
    print("=== website checks:", SITE)
    index = SITE / "index.html"
    page = parse(index)

    print("\n--- assets & cache-busting")
    missing = []
    for ref in page.refs:
        lp = local_path(ref)
        if lp is not None and not lp.exists():
            missing.append(ref)
    check(not missing, f"all local assets referenced by index.html exist {missing or ''}")
    for name, attr in (("styles.css", "href"), ("app.js", "src")):
        digest = hashlib.sha1((SITE / name).read_bytes()).hexdigest()[:8]
        refs = [r for r in page.refs if r.split("?")[0] == name]
        check(refs == [f"{name}?v={digest}"], f"{name} stamped with its content hash ({refs} vs v={digest})")
    insecure = [r for r in page.refs if r.startswith("http://")]
    check(not insecure, f"no mixed-content (http://) resources {insecure or ''}")

    print("\n--- on-page SEO")
    check(page.h1 == 1, f"exactly one <h1> (found {page.h1})")
    check(10 <= len(page.title.strip()) <= 60, f"<title> 10–60 chars ({len(page.title.strip())})")
    desc = page.meta.get("description", "")
    check(70 <= len(desc) <= 160, f"meta description 70–160 chars ({len(desc)})")
    canon = [l.get("href") for l in page.links if l.get("rel") == "canonical"]
    check(canon == [f"{ORIGIN}/"], f"canonical is {ORIGIN}/ ({canon})")
    check(page.meta.get("og:url") == f"{ORIGIN}/", "og:url matches canonical")

    print("\n--- structured data (JSON-LD)")
    ids_defined, ids_used = set(), set()

    def walk(node, top=False):
        if isinstance(node, dict):
            if "@id" in node:
                (ids_defined if (top or len(node) > 1) else ids_used).add(node["@id"])
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    ok_json = True
    for block in page.jsonld:
        try:
            data = json.loads(block)
        except json.JSONDecodeError as e:
            ok_json = False
            print("      ", e)
            continue
        for node in data.get("@graph", [data]):
            walk(node, top=True)
    check(ok_json and bool(page.jsonld), "JSON-LD blocks parse")
    dangling = sorted(ids_used - ids_defined)
    check(not dangling, f"every JSON-LD @id reference is defined in the graph {dangling or ''}")

    print("\n--- social preview")
    og = page.meta.get("og:image", "")
    ogp = local_path(og)
    check(og.startswith(f"{ORIGIN}/") and ogp is not None and ogp.exists(), f"og:image is an absolute {ORIGIN} URL to a file in website/ ({og})")
    if ogp is not None and ogp.exists():
        size = image_size(ogp)
        check(size == (1200, 630), f"og:image is 1200×630 ({size})")
        kb = ogp.stat().st_size // 1024
        check(kb <= 300, f"og:image ≤ 300 KB ({kb} KB)")
        check(page.meta.get("og:image:width") == str(size[0]) and page.meta.get("og:image:height") == str(size[1]) if size else False,
              "og:image:width/height match the file")
    check(bool(page.meta.get("og:image:alt")), "og:image:alt present")
    check(page.meta.get("twitter:image") == og, "twitter:image matches og:image")
    check(page.meta.get("twitter:card") == "summary_large_image", "twitter:card = summary_large_image")

    print("\n--- image weight")
    heavy = []
    for ref in set(page.refs):
        lp = local_path(ref)
        if lp and lp.exists() and lp.suffix.lower() in (".png", ".jpg", ".jpeg") and lp.stat().st_size > 200 * 1024:
            heavy.append(f"{ref} ({lp.stat().st_size // 1024} KB)")
    check(not heavy, f"no image over 200 KB loaded by the page {heavy or ''}")

    print("\n--- crawler files")
    robots = (SITE / "robots.txt").read_text()
    check(f"Sitemap: {ORIGIN}/sitemap.xml" in robots, "robots.txt points to the sitemap")
    check(not re.search(r"(?im)^Disallow:\s*/\s*$", robots), "robots.txt does not block the whole site")
    sitemap = (SITE / "sitemap.xml").read_text()
    locs = re.findall(r"<loc>([^<]+)</loc>", sitemap)
    check(locs and all(l.startswith(f"{ORIGIN}/") for l in locs), f"sitemap URLs are on {ORIGIN} ({locs})")
    check(all(re.fullmatch(r"\d{4}-\d{2}-\d{2}", d) for d in re.findall(r"<lastmod>([^<]+)</lastmod>", sitemap)), "sitemap lastmod values are W3C dates")
    llms = (SITE / "llms.txt").read_text()
    check(llms.startswith("# ") and "\n> " in llms, "llms.txt has an H1 and a > summary")
    md_links = re.findall(r"\[[^\]]+\]\((https://[^)]+)\)", llms)
    check(len(md_links) >= 3, f"llms.txt lists absolute Markdown links ({len(md_links)})")
    full = SITE / "llms-full.txt"
    check(full.exists() and full.read_text().startswith("# "), "llms-full.txt exists")

    print("\n--- Cloudflare Pages: 404 page, redirects, headers")
    notfound = SITE / "404.html"
    check(notfound.exists(), "404.html exists (otherwise Pages answers every unknown URL with the homepage and HTTP 200)")
    nf = parse(notfound) if notfound.exists() else None
    if nf:
        check("noindex" in nf.meta.get("robots", ""), "404.html is noindex")
        nf_missing = [r for r in nf.refs if (lp := local_path(r)) is not None and not lp.exists()]
        check(not nf_missing, f"404.html assets exist {nf_missing or ''}")
    redirects = SITE / "_redirects"
    check(redirects.exists() and "/privacy.html" in redirects.read_text(), "_redirects keeps the old /privacy.html and /terms.html URLs working")
    headers = SITE / "_headers"
    check(headers.exists(), "_headers exists")
    if headers.exists():
        text = headers.read_text()
        for h in ("Content-Security-Policy", "Strict-Transport-Security", "X-Content-Type-Options", "Referrer-Policy", "Permissions-Policy", "X-Frame-Options"):
            check(f"{h}:" in text, f"_headers sets {h}")
        csp = csp_directives(text)
        check("'unsafe-eval'" not in sum(csp.values(), []), "CSP does not allow 'unsafe-eval'")
        check("'unsafe-inline'" not in csp.get("script-src", []), "CSP script-src does not allow 'unsafe-inline'")
        check(csp.get("frame-ancestors") == ["'none'"], "CSP frame-ancestors 'none'")
        for pg_name, pg in (("index.html", page), ("404.html", nf)):
            if pg is None:
                continue
            for s in pg.scripts:
                src = s.get("src", "")
                if src.startswith("http"):
                    o = "{0.scheme}://{0.netloc}".format(urlparse(src))
                    check(o in csp.get("script-src", []), f"CSP script-src allows {o} ({pg_name})")
                    check(o in csp.get("connect-src", []), f"CSP connect-src allows {o} (analytics beacons, {pg_name})")
                elif not src and s.get("type") != "application/ld+json":
                    check(False, f"no inline executable <script> in {pg_name} (CSP blocks it)")

    print("\n--- privacy notice vs. third-party scripts")
    privacy = re.sub(r"\s+", " ", page.text_by_id.get("legal-privacy", ""))
    third_party = sorted({urlparse(s["src"]).netloc for s in page.scripts if s.get("src", "").startswith("http")})
    check(bool(privacy), "privacy modal found")
    for host in third_party:
        name = host.split(".")[-2]
        check(name.lower() in privacy.lower(), f"privacy notice discloses the third-party script from {host}")
    if third_party:
        check("no cookies or trackers" not in privacy.lower(), "privacy notice doesn't claim the website has no trackers while loading analytics")

    print(f"\nSummary: {len(failures)} fail, {passes} pass")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
