#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import plistlib
import re
import stat
import zipfile
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_APP_PATH = (
    REPO_ROOT
    / ".DerivedData"
    / "build"
    / "Build"
    / "Products"
    / "Release"
    / "Shorty.app"
)
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".build" / "releases"
PACKAGE_VERSION_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")
ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)


class AppPackageError(RuntimeError):
    """Raised when a macOS app package cannot be produced."""


@dataclass(frozen=True)
class AppPackageResult:
    archive_path: Path
    checksum_path: Path
    digest: str


def validate_package_version(version: str) -> str:
    normalized = version.strip()
    if not PACKAGE_VERSION_PATTERN.fullmatch(normalized):
        raise AppPackageError(
            "Package version must contain only letters, numbers, dots, "
            f"underscores, or hyphens; received {version!r}."
        )
    return normalized


def app_bundle_version(app_path: Path) -> str:
    info_plist = app_path / "Contents" / "Info.plist"
    if not info_plist.is_file():
        raise AppPackageError(f"App Info.plist not found: {info_plist}")

    with info_plist.open("rb") as file:
        info = plistlib.load(file)

    version = info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or not version.strip():
        raise AppPackageError(f"App bundle version missing from {info_plist}")
    return version


def iter_bundle_paths(app_path: Path) -> list[Path]:
    if not app_path.is_dir():
        raise AppPackageError(f"App bundle not found: {app_path}")

    paths = [app_path]
    paths.extend(path for path in app_path.rglob("*") if path.name != ".DS_Store")
    return sorted(paths, key=lambda path: path.relative_to(app_path.parent).as_posix())


def zip_info_for(path: Path, app_parent: Path) -> zipfile.ZipInfo:
    arcname = path.relative_to(app_parent).as_posix()
    if not path.is_symlink() and path.is_dir() and not arcname.endswith("/"):
        arcname += "/"

    info = zipfile.ZipInfo(arcname, ZIP_TIMESTAMP)
    info.create_system = 3
    mode = path.lstat().st_mode
    if path.is_symlink():
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
    elif path.is_dir():
        info.external_attr = (stat.S_IFDIR | 0o755) << 16
    else:
        info.external_attr = (stat.S_IFREG | stat.S_IMODE(mode)) << 16
    return info


def add_path_to_zip(archive: zipfile.ZipFile, path: Path, app_parent: Path) -> None:
    info = zip_info_for(path, app_parent)
    if path.is_symlink():
        archive.writestr(info, path.readlink().as_posix().encode("utf-8"))
    elif path.is_dir():
        archive.writestr(info, b"")
    else:
        archive.writestr(info, path.read_bytes())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_app(app_path: Path, version: str, output_dir: Path) -> AppPackageResult:
    normalized_version = validate_package_version(version)
    resolved_app_path = app_path.resolve()
    bundle_version = app_bundle_version(resolved_app_path)
    if bundle_version != normalized_version:
        raise AppPackageError(
            f"Requested version {normalized_version} does not match app bundle "
            f"version {bundle_version}."
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = output_dir / f"shorty-{normalized_version}-macos.zip"
    checksum_path = output_dir / f"{archive_path.name}.sha256"

    paths = iter_bundle_paths(resolved_app_path)
    with zipfile.ZipFile(
        archive_path,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for path in paths:
            add_path_to_zip(archive, path, resolved_app_path.parent)

    digest = sha256_file(archive_path)
    checksum_path.write_text(f"{digest}  {archive_path.name}\n", encoding="utf-8")
    return AppPackageResult(
        archive_path=archive_path,
        checksum_path=checksum_path,
        digest=digest,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Package the Shorty macOS app.")
    parser.add_argument("--version", required=True, help="Release version label.")
    parser.add_argument(
        "--app-path",
        default=str(DEFAULT_APP_PATH),
        help="Built Shorty.app path.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory where release artifacts should be written.",
    )
    args = parser.parse_args(argv)

    try:
        result = package_app(
            app_path=Path(args.app_path),
            version=args.version,
            output_dir=Path(args.output_dir),
        )
    except AppPackageError as error:
        print(f"ERROR: {error}")
        return 2

    print(f"Created {result.archive_path}")
    print(f"Created {result.checksum_path}")
    print(f"SHA256 {result.digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
