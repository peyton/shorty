#!/usr/bin/env python3

from __future__ import annotations

import argparse
import gzip
import hashlib
import re
import tarfile
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SOURCE_ROOT = REPO_ROOT / ".build" / "web"
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".build" / "releases"
PACKAGE_VERSION_PATTERN = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*")


class PackageError(RuntimeError):
    """Raised when the static site cannot be packaged."""


@dataclass(frozen=True)
class PackageResult:
    archive_path: Path
    checksum_path: Path
    digest: str


def validate_package_version(version: str) -> str:
    normalized = version.strip()
    if not PACKAGE_VERSION_PATTERN.fullmatch(normalized):
        raise PackageError(
            "Package version must contain only letters, numbers, dots, "
            f"underscores, or hyphens; received {version!r}."
        )
    return normalized


def iter_package_files(source_root: Path) -> list[Path]:
    resolved_root = source_root.resolve()
    if not resolved_root.is_dir():
        raise PackageError(f"Static site build output not found: {source_root}")

    return sorted(path for path in resolved_root.rglob("*") if path.is_file())


def add_file_to_tar(tar: tarfile.TarFile, source_root: Path, path: Path) -> None:
    arcname = path.relative_to(source_root).as_posix()
    info = tar.gettarinfo(str(path), arcname=arcname)
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    info.mtime = 0
    with path.open("rb") as file:
        tar.addfile(info, file)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_site(
    source_root: Path,
    version: str,
    output_dir: Path,
) -> PackageResult:
    normalized_version = validate_package_version(version)
    resolved_source_root = source_root.resolve()
    files = iter_package_files(resolved_source_root)
    output_dir.mkdir(parents=True, exist_ok=True)

    archive_path = output_dir / f"shorty-web-{normalized_version}.tar.gz"
    checksum_path = output_dir / f"{archive_path.name}.sha256"

    with archive_path.open("wb") as raw_archive:
        with gzip.GzipFile(
            filename="",
            mode="wb",
            fileobj=raw_archive,
            mtime=0,
        ) as gzip_archive:
            with tarfile.open(fileobj=gzip_archive, mode="w") as tar:
                for path in files:
                    add_file_to_tar(tar, resolved_source_root, path)

    digest = sha256_file(archive_path)
    checksum_path.write_text(f"{digest}  {archive_path.name}\n", encoding="utf-8")
    return PackageResult(
        archive_path=archive_path,
        checksum_path=checksum_path,
        digest=digest,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Package the Shorty static site.")
    parser.add_argument("--version", required=True, help="Package version label.")
    parser.add_argument(
        "--source-root",
        default=str(DEFAULT_SOURCE_ROOT),
        help="Built static site directory to package.",
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory where release artifacts should be written.",
    )
    args = parser.parse_args(argv)

    try:
        result = package_site(
            source_root=Path(args.source_root),
            version=args.version,
            output_dir=Path(args.output_dir),
        )
    except PackageError as error:
        print(f"ERROR: {error}")
        return 2

    print(f"Created {result.archive_path}")
    print(f"Created {result.checksum_path}")
    print(f"SHA256 {result.digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
