#!/usr/bin/env python3

from __future__ import annotations

import argparse
import email.utils
import os
import xml.etree.ElementTree as ET
from pathlib import Path

from scripts.tooling.package_app import (
    DEFAULT_OUTPUT_DIR,
    sha256_file,
    validate_package_version,
)


class AppcastGenerateError(RuntimeError):
    """Raised when an appcast cannot be generated."""


def generate_appcast(
    version: str,
    archive_path: Path,
    download_url: str,
    output_path: Path,
    ed_signature: str | None,
    allow_unsigned: bool = False,
    source_url: str | None = None,
) -> Path:
    normalized_version = validate_package_version(version)
    source_url = source_url or (
        f"https://github.com/peyton/shorty/releases/tag/v{normalized_version}"
    )
    if not archive_path.is_file():
        raise AppcastGenerateError(f"Archive not found: {archive_path}")
    if not ed_signature and not allow_unsigned:
        raise AppcastGenerateError(
            "Sparkle appcast generation requires an EdDSA signature. Pass "
            "--ed-signature or set SHORTY_SPARKLE_ED_SIGNATURE."
        )

    rss = ET.Element("rss", {"version": "2.0"})
    rss.set("xmlns:sparkle", "http://www.andymatuschak.org/xml-namespaces/sparkle")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Shorty Updates"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"Shorty {normalized_version}"
    ET.SubElement(item, "link").text = source_url
    ET.SubElement(item, "pubDate").text = email.utils.formatdate(usegmt=True)
    ET.SubElement(item, "sparkle:version").text = normalized_version
    ET.SubElement(item, "sparkle:shortVersionString").text = normalized_version
    ET.SubElement(item, "sparkle:releaseNotesLink").text = source_url

    enclosure_attributes = {
        "url": download_url,
        "length": str(archive_path.stat().st_size),
        "type": "application/octet-stream",
        "sparkle:sha256": sha256_file(archive_path),
    }
    if ed_signature:
        enclosure_attributes["sparkle:edSignature"] = ed_signature
    ET.SubElement(item, "enclosure", enclosure_attributes)

    tree = ET.ElementTree(rss)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(tree, space="  ")
    tree.write(output_path, encoding="utf-8", xml_declaration=True)
    return output_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate a Sparkle appcast.")
    parser.add_argument("--version", required=True)
    parser.add_argument(
        "--archive-path",
        help=(
            "Release archive path. Defaults to "
            ".build/releases/shorty-VERSION-macos.zip."
        ),
    )
    parser.add_argument("--download-url", required=True)
    parser.add_argument(
        "--output-path",
        default=str(DEFAULT_OUTPUT_DIR / "appcast.xml"),
    )
    parser.add_argument(
        "--ed-signature",
        default=os.environ.get("SHORTY_SPARKLE_ED_SIGNATURE"),
    )
    parser.add_argument(
        "--source-url",
        help=(
            "Release/source page URL. Defaults to the GitHub release tag for "
            "the requested version."
        ),
    )
    parser.add_argument("--allow-unsigned", action="store_true")
    args = parser.parse_args(argv)

    version = validate_package_version(args.version)
    archive_path = (
        Path(args.archive_path)
        if args.archive_path
        else (DEFAULT_OUTPUT_DIR / f"shorty-{version}-macos.zip")
    )
    try:
        output_path = generate_appcast(
            version=version,
            archive_path=archive_path,
            download_url=args.download_url,
            output_path=Path(args.output_path),
            ed_signature=args.ed_signature,
            allow_unsigned=args.allow_unsigned,
            source_url=args.source_url,
        )
    except AppcastGenerateError as error:
        print(f"ERROR: {error}")
        return 2

    print(f"Created {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
