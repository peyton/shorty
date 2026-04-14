# Shorty Web

The static website lives in `web/` and uses plain HTML and CSS. It is intentionally dependency-light so it can be previewed locally, checked in CI, and packaged as a small artifact.

## Commands

- `just web-serve`
  - Serves `web/` locally with Python's static file server.
- `just web-check`
  - Runs Prettier check for HTML/CSS and validates required files, metadata, support email, sitemap, robots, and internal links.
- `just web-fmt`
  - Formats HTML and CSS with Prettier.
- `just web-build`
  - Validates the site and copies it to `.build/web/`.
- `just web-package VERSION=test`
  - Builds and packages `.build/web/` into `.build/releases/shorty-web-test.tar.gz` with a matching `.sha256` file.

## Release Copy

The public site points users to the latest GitHub release for the macOS app
archive. Keep the download language aligned with the app release tooling:

- app archive: `shorty-<version>-macos.zip`
- checksum: `shorty-<version>-macos.zip.sha256`
- verification command: `shasum -a 256 shorty-<version>-macos.zip`

Support copy should keep the browser bridge clearly optional. Native app
shortcut remapping is the primary release path.

## Public Defaults

The initial site assumes:

- Canonical origin: `https://shorty.peyton.app/`
- Support email: `shorty@peyton.app`

Update `scripts/web/validate_static_site.py`, `web/robots.txt`, `web/sitemap.xml`, and site metadata together if those public values change.
