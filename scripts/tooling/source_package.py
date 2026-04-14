#!/usr/bin/env python3

from __future__ import annotations

import argparse
import gzip
import hashlib
import io
import stat
import subprocess
import tarfile
from dataclasses import dataclass
from pathlib import Path

from scripts.tooling.package_app import (
    DEFAULT_OUTPUT_DIR,
    REPO_ROOT,
    validate_package_version,
)

SOURCE_TIMESTAMP = 0
SOURCE_EXCLUDES = {
    ".git",
    ".build",
    ".cache",
    ".config",
    ".DerivedData",
    ".mise",
    ".pytest_cache",
    ".ruff_cache",
    ".rumdl_cache",
    ".state",
    ".venv",
    "node_modules",
}


class SourcePackageError(RuntimeError):
    """Raised when a source package cannot be produced."""


@dataclass(frozen=True)
class SourcePackageResult:
    archive_path: Path
    checksum_path: Path
    digest: str
    file_count: int


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_source_files(repo_root: Path = REPO_ROOT) -> list[Path]:
    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=repo_root,
        check=True,
        capture_output=True,
    )
    files: list[Path] = []
    for raw_entry in result.stdout.split(b"\0"):
        if not raw_entry:
            continue
        relative = Path(raw_entry.decode("utf-8"))
        if should_include_source_path(relative):
            files.append(relative)
    return sorted(files, key=lambda path: path.as_posix())


def should_include_source_path(relative_path: Path) -> bool:
    return not any(part in SOURCE_EXCLUDES for part in relative_path.parts)


def tar_info_for(
    relative_path: Path,
    source_path: Path,
    archive_root: str,
) -> tarfile.TarInfo:
    arcname = f"{archive_root}/{relative_path.as_posix()}"
    mode = source_path.lstat().st_mode
    info = tarfile.TarInfo(arcname)
    info.mtime = SOURCE_TIMESTAMP
    info.uid = 0
    info.gid = 0
    info.uname = ""
    info.gname = ""
    if source_path.is_symlink():
        info.type = tarfile.SYMTYPE
        info.mode = 0o777
        info.linkname = source_path.readlink().as_posix()
    else:
        info.type = tarfile.REGTYPE
        info.mode = stat.S_IMODE(mode)
        info.size = source_path.stat().st_size
    return info


def add_source_file(
    archive: tarfile.TarFile,
    repo_root: Path,
    relative_path: Path,
    archive_root: str,
) -> None:
    source_path = repo_root / relative_path
    if not source_path.is_file() and not source_path.is_symlink():
        return

    info = tar_info_for(relative_path, source_path, archive_root)
    if source_path.is_symlink():
        archive.addfile(info)
        return

    with source_path.open("rb") as file:
        archive.addfile(info, file)


def create_source_archive(
    files: list[Path],
    repo_root: Path,
    archive_path: Path,
    archive_root: str,
) -> None:
    buffer = io.BytesIO()
    with gzip.GzipFile(
        filename="",
        mode="wb",
        fileobj=buffer,
        mtime=SOURCE_TIMESTAMP,
    ) as gzip_file:
        with tarfile.open(fileobj=gzip_file, mode="w") as archive:
            for relative_path in files:
                add_source_file(archive, repo_root, relative_path, archive_root)

    archive_path.write_bytes(buffer.getvalue())


def package_source(
    version: str,
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    repo_root: Path = REPO_ROOT,
) -> SourcePackageResult:
    normalized_version = validate_package_version(version)
    files = git_source_files(repo_root)
    if not files:
        raise SourcePackageError("No source files found to package.")

    output_dir.mkdir(parents=True, exist_ok=True)
    archive_path = output_dir / f"shorty-{normalized_version}-source.tar.gz"
    checksum_path = output_dir / f"{archive_path.name}.sha256"
    archive_root = f"shorty-{normalized_version}"

    create_source_archive(files, repo_root, archive_path, archive_root)
    digest = sha256_file(archive_path)
    checksum_path.write_text(f"{digest}  {archive_path.name}\n", encoding="utf-8")
    return SourcePackageResult(
        archive_path=archive_path,
        checksum_path=checksum_path,
        digest=digest,
        file_count=len(files),
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Package Shorty source files.")
    parser.add_argument("--version", required=True, help="Release version label.")
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory where release artifacts should be written.",
    )
    args = parser.parse_args(argv)

    try:
        result = package_source(
            version=args.version,
            output_dir=Path(args.output_dir),
        )
    except (SourcePackageError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}")
        return 2

    print(f"Created {result.archive_path}")
    print(f"Created {result.checksum_path}")
    print(f"Packaged {result.file_count} source files")
    print(f"SHA256 {result.digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
