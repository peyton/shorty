from __future__ import annotations

import json
import struct
import tarfile
from pathlib import Path
from xml.etree import ElementTree

from scripts.web.package_static_site import package_site, sha256_file
from scripts.web.validate_static_site import validate_site

REPO_ROOT = Path(__file__).resolve().parents[1]
SVG_NAMESPACE = "{http://www.w3.org/2000/svg}"
BRAND_SVG_ASSETS = (
    "app-icon.svg",
    "command-map-hero.svg",
    "glyph-native.svg",
    "glyph-bridge.svg",
    "glyph-checksum.svg",
    "glyph-diagnostics.svg",
    "glyph-support.svg",
)
APP_ICON_SIZES = {
    "app-icon-16.png": (16, 16),
    "app-icon-32.png": (32, 32),
    "app-icon-32-1x.png": (32, 32),
    "app-icon-64.png": (64, 64),
    "app-icon-128.png": (128, 128),
    "app-icon-256.png": (256, 256),
    "app-icon-256-1x.png": (256, 256),
    "app-icon-512.png": (512, 512),
    "app-icon-512-1x.png": (512, 512),
    "app-icon-1024.png": (1024, 1024),
}


def test_committed_static_site_is_review_ready() -> None:
    errors = validate_site(REPO_ROOT / "web")

    assert errors == []


def test_brand_svg_assets_are_committed_with_metadata() -> None:
    asset_root = REPO_ROOT / "web" / "assets"

    for asset_name in BRAND_SVG_ASSETS:
        asset_path = asset_root / asset_name

        assert asset_path.is_file()

        root = ElementTree.fromstring(asset_path.read_text(encoding="utf-8"))
        title = root.find(f"{SVG_NAMESPACE}title")
        desc = root.find(f"{SVG_NAMESPACE}desc")

        assert title is not None
        assert title.text
        assert desc is not None
        assert desc.text


def test_macos_app_icon_catalog_has_rendered_slots() -> None:
    icon_root = (
        REPO_ROOT
        / "app"
        / "Shorty"
        / "Sources"
        / "Shorty"
        / "Resources"
        / "Assets.xcassets"
        / "AppIcon.appiconset"
    )
    contents = json.loads((icon_root / "Contents.json").read_text(encoding="utf-8"))
    filenames = {
        image["filename"] for image in contents["images"] if "filename" in image
    }

    assert filenames == set(APP_ICON_SIZES)
    for filename, expected_size in APP_ICON_SIZES.items():
        assert png_size(icon_root / filename) == expected_size


def test_static_site_validator_rejects_placeholder_and_missing_contact(
    tmp_path: Path,
) -> None:
    site_root = tmp_path / "web"
    site_root.mkdir()
    (site_root / "support").mkdir()
    (site_root / "privacy").mkdir()
    (site_root / "assets").mkdir()
    (site_root / "assets" / "site.css").write_text("body { color: #111; }\n")
    (site_root / "robots.txt").write_text(
        "User-agent: *\nAllow: /\nSitemap: https://shorty.peyton.app/sitemap.xml\n"
    )
    (site_root / "sitemap.xml").write_text(
        """
        <urlset>
          <url><loc>https://shorty.peyton.app/</loc></url>
          <url><loc>https://shorty.peyton.app/support/</loc></url>
          <url><loc>https://shorty.peyton.app/privacy/</loc></url>
        </urlset>
        """,
        encoding="utf-8",
    )
    broken_page = """
        <!doctype html>
        <html lang="en">
          <head>
            <title>Broken</title>
            <meta name="description" content="Broken page">
          </head>
          <body>
            <a href="#">Download on the App Store</a>
            <a href="/missing/">Missing</a>
          </body>
        </html>
        """
    for relative_path in (
        "index.html",
        "support/index.html",
        "privacy/index.html",
        "404.html",
    ):
        (site_root / relative_path).write_text(broken_page, encoding="utf-8")

    errors = validate_site(site_root)

    assert any("placeholder link" in error for error in errors)
    assert any("missing public support email" in error for error in errors)
    assert any("download on the app store" in error for error in errors)
    assert any("broken internal" in error for error in errors)


def test_static_site_package_contains_relative_site_files(tmp_path: Path) -> None:
    source_root = tmp_path / "web-build"
    source_root.mkdir()
    (source_root / "assets").mkdir()
    (source_root / "index.html").write_text("<!doctype html>\n", encoding="utf-8")
    (source_root / "assets" / "site.css").write_text(
        "body { color: #111; }\n",
        encoding="utf-8",
    )
    output_dir = tmp_path / "releases"

    result = package_site(source_root, "1.2.3", output_dir)

    assert result.archive_path == output_dir / "shorty-web-1.2.3.tar.gz"
    assert result.checksum_path == output_dir / "shorty-web-1.2.3.tar.gz.sha256"
    assert result.digest == sha256_file(result.archive_path)
    assert (
        result.checksum_path.read_text(encoding="utf-8")
        == f"{result.digest}  shorty-web-1.2.3.tar.gz\n"
    )

    with tarfile.open(result.archive_path, "r:gz") as archive:
        assert archive.getnames() == ["assets/site.css", "index.html"]
        for member in archive.getmembers():
            assert member.uid == 0
            assert member.gid == 0
            assert member.mtime == 0


def png_size(path: Path) -> tuple[int, int]:
    header = path.read_bytes()[:24]

    assert header[:8] == b"\x89PNG\r\n\x1a\n"
    return struct.unpack(">II", header[16:24])
