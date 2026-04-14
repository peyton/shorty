from __future__ import annotations

import tarfile
from pathlib import Path

from scripts.web.package_static_site import package_site, sha256_file
from scripts.web.validate_static_site import validate_site

REPO_ROOT = Path(__file__).resolve().parents[1]


def test_committed_static_site_is_review_ready() -> None:
    errors = validate_site(REPO_ROOT / "web")

    assert errors == []


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
