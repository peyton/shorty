#!/usr/bin/env python3

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlparse

SUPPORT_EMAIL = "shorty@peyton.app"
SITE_ORIGIN = "https://shorty.peyton.app"
REQUIRED_FILES = (
    "index.html",
    "support/index.html",
    "privacy/index.html",
    "license/index.html",
    "404.html",
    "robots.txt",
    "sitemap.xml",
)
HTML_FILE_GLOBS = ("*.html",)
ALLOWED_EXTERNAL_SCHEMES = ("https", "mailto", "tel")
FORBIDDEN_PHRASES = (
    "lorem ipsum",
    "todo",
    "coming soon",
    "download on the app store",
    'href="#"',
    "href='#'",
    "placeholder",
)


@dataclass
class LinkReference:
    attribute: str
    target: str
    line: int


@dataclass
class ParsedHtml:
    title: str = ""
    meta_description: str = ""
    links: list[LinkReference] = field(default_factory=list)


class StaticSiteParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parsed = ParsedHtml()
        self._in_title = False
        self._title_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        normalized = dict(attrs)
        if tag == "title":
            self._in_title = True
        if tag == "meta" and normalized.get("name", "").lower() == "description":
            self.parsed.meta_description = (normalized.get("content") or "").strip()

        for attribute in ("href", "src"):
            value = normalized.get(attribute)
            if value:
                self.parsed.links.append(
                    LinkReference(
                        attribute=attribute,
                        target=value.strip(),
                        line=self.getpos()[0],
                    )
                )

    def handle_endtag(self, tag: str) -> None:
        if tag == "title":
            self._in_title = False
            self.parsed.title = " ".join("".join(self._title_parts).split())

    def handle_data(self, data: str) -> None:
        if self._in_title:
            self._title_parts.append(data)


def parse_html(value: str) -> ParsedHtml:
    parser = StaticSiteParser()
    parser.feed(value)
    parser.close()
    return parser.parsed


def html_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for pattern in HTML_FILE_GLOBS:
        files.extend(root.rglob(pattern))
    return sorted(path for path in files if path.is_file())


def resolve_internal_target(root: Path, source: Path, raw_target: str) -> Path | None:
    target = raw_target.split("#", 1)[0].split("?", 1)[0]
    if not target:
        return None

    parsed = urlparse(target)
    if parsed.scheme:
        return None

    if target.startswith("/"):
        candidate = root / unquote(target.lstrip("/"))
    else:
        candidate = source.parent / unquote(target)

    if target.endswith("/") or candidate.is_dir():
        candidate = candidate / "index.html"

    return candidate.resolve()


def validate_internal_link(root: Path, source: Path, link: LinkReference) -> str | None:
    target = link.target
    parsed = urlparse(target)
    if parsed.scheme:
        if parsed.scheme not in ALLOWED_EXTERNAL_SCHEMES:
            return (
                f"{source.relative_to(root)}:{link.line}: unsupported URL scheme "
                f"{parsed.scheme!r} in {link.attribute}={target!r}."
            )
        if parsed.scheme == "http":
            return f"{source.relative_to(root)}:{link.line}: insecure URL {target!r}."
        return None

    if target == "#":
        return (
            f'{source.relative_to(root)}:{link.line}: placeholder link href="#" '
            "is not allowed."
        )

    candidate = resolve_internal_target(root, source, target)
    if candidate is None:
        return None

    try:
        candidate.relative_to(root.resolve())
    except ValueError:
        return (
            f"{source.relative_to(root)}:{link.line}: link escapes web root: "
            f"{target!r}."
        )

    if not candidate.exists():
        expected = candidate.relative_to(root.resolve())
        return (
            f"{source.relative_to(root)}:{link.line}: broken internal "
            f"{link.attribute}={target!r}; expected {expected}."
        )

    return None


def validate_html_file(root: Path, path: Path) -> list[str]:
    errors: list[str] = []
    raw = path.read_text(encoding="utf-8")
    lowered = raw.lower()
    relative = path.relative_to(root)
    parsed = parse_html(raw)

    if "noindex" in lowered:
        errors.append(f"{relative}: must not contain noindex.")
    if "http://" in lowered:
        errors.append(f"{relative}: must not contain insecure http:// URLs.")
    if SUPPORT_EMAIL not in raw:
        errors.append(f"{relative}: missing public support email {SUPPORT_EMAIL}.")
    if not parsed.title:
        errors.append(f"{relative}: missing non-empty <title>.")
    if not parsed.meta_description:
        errors.append(f"{relative}: missing non-empty meta description.")

    for phrase in FORBIDDEN_PHRASES:
        if phrase in lowered:
            errors.append(
                f"{relative}: contains forbidden stale or placeholder copy {phrase!r}."
            )

    for link in parsed.links:
        link_error = validate_internal_link(root, path, link)
        if link_error:
            errors.append(link_error)

    return errors


def validate_site(root: Path) -> list[str]:
    resolved_root = root.resolve()
    errors: list[str] = []

    if not resolved_root.is_dir():
        return [f"Static site root not found: {root}"]

    for required_file in REQUIRED_FILES:
        path = resolved_root / required_file
        if not path.is_file():
            errors.append(f"Missing required static site file: {required_file}")

    robots = resolved_root / "robots.txt"
    expected_sitemap = f"Sitemap: {SITE_ORIGIN}/sitemap.xml"
    if robots.is_file() and expected_sitemap not in robots.read_text(encoding="utf-8"):
        errors.append(f"robots.txt must reference {SITE_ORIGIN}/sitemap.xml.")

    sitemap = resolved_root / "sitemap.xml"
    if sitemap.is_file():
        sitemap_text = sitemap.read_text(encoding="utf-8")
        for path in ("/", "/support/", "/privacy/", "/license/"):
            expected = f"{SITE_ORIGIN}{path}"
            if expected not in sitemap_text:
                errors.append(f"sitemap.xml missing {expected}.")
        sitemap_urls = sitemap_text.replace(
            'xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"',
            "",
        )
        if "http://" in sitemap_urls:
            errors.append("sitemap.xml must not contain insecure http:// URLs.")

    for path in html_files(resolved_root):
        errors.extend(validate_html_file(resolved_root, path))

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate the Shorty static web site.")
    parser.add_argument(
        "root",
        nargs="?",
        default="web",
        help="Static site root to validate.",
    )
    args = parser.parse_args()

    errors = validate_site(Path(args.root))
    if errors:
        print(f"Static site validation failed for {args.root}:")
        for error in errors:
            print(f"- ERROR: {error}")
        return 1

    print(f"Static site validation passed for {args.root}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
