#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import plistlib
import shutil
import subprocess
import tempfile
import zipfile
from dataclasses import dataclass
from pathlib import Path

from scripts.tooling.package_app import (
    DEFAULT_OUTPUT_DIR,
    AppPackageError,
    validate_package_label,
    validate_package_version,
)
from scripts.tooling.safari_extension_verify import (
    SafariExtensionVerificationError,
    verify_safari_extension,
)


class ReleaseVerificationError(RuntimeError):
    """Raised when a release artifact fails verification."""


@dataclass(frozen=True)
class ReleaseVerificationResult:
    version: str
    archive_path: Path
    digest: str
    extracted_app_path: Path


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_checksum(archive_path: Path, checksum_path: Path) -> str:
    if not archive_path.is_file():
        raise ReleaseVerificationError(f"Release archive not found: {archive_path}")
    if not checksum_path.is_file():
        raise ReleaseVerificationError(f"Checksum file not found: {checksum_path}")

    digest = sha256(archive_path)
    expected_line = checksum_path.read_text(encoding="utf-8").strip()
    expected_digest = expected_line.split()[0] if expected_line else ""
    if digest != expected_digest:
        raise ReleaseVerificationError(
            f"Checksum mismatch for {archive_path.name}: expected "
            f"{expected_digest}, got {digest}"
        )
    return digest


def extracted_app_version(app_path: Path) -> str:
    info_plist = app_path / "Contents" / "Info.plist"
    if not info_plist.is_file():
        raise ReleaseVerificationError(f"Extracted app missing Info.plist: {app_path}")
    with info_plist.open("rb") as file:
        info = plistlib.load(file)
    version = info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or not version:
        raise ReleaseVerificationError("Extracted app missing bundle version.")
    return version


def run_gatekeeper_assessment(app_path: Path) -> None:
    subprocess.run(
        ["spctl", "--assess", "--type", "execute", "--verbose=4", str(app_path)],
        check=True,
        capture_output=True,
        text=True,
    )


def run_staple_validation(app_path: Path) -> None:
    subprocess.run(
        ["xcrun", "stapler", "validate", str(app_path)],
        check=True,
        capture_output=True,
        text=True,
    )


def extract_zip_preserving_symlinks(archive_path: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive_path) as archive:
        for info in archive.infolist():
            target = destination / info.filename
            file_type = (info.external_attr >> 16) & 0o170000
            if info.is_dir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            if file_type == 0o120000:
                link_target = archive.read(info).decode("utf-8")
                if target.exists() or target.is_symlink():
                    target.unlink()
                target.symlink_to(link_target)
            else:
                with target.open("wb") as file:
                    file.write(archive.read(info))


def verify_release(
    version: str,
    archive_path: Path,
    checksum_path: Path,
    artifact_label: str | None = None,
    require_codesign: bool = False,
    require_gatekeeper: bool = False,
    require_staple: bool = False,
) -> ReleaseVerificationResult:
    normalized_version = validate_package_version(version)
    validate_package_label(artifact_label or normalized_version, normalized_version)
    digest = verify_checksum(archive_path, checksum_path)

    temp_dir = Path(tempfile.mkdtemp(prefix="shorty-release-verify-"))
    try:
        extract_zip_preserving_symlinks(archive_path, temp_dir)
        app_path = temp_dir / "Shorty.app"
        if not app_path.is_dir():
            raise ReleaseVerificationError(
                "Release archive did not contain Shorty.app."
            )

        bundle_version = extracted_app_version(app_path)
        if bundle_version != normalized_version:
            raise ReleaseVerificationError(
                f"Expected app version {normalized_version}, found {bundle_version}."
            )

        verify_safari_extension(
            app_path=app_path,
            require_codesign=require_codesign,
        )

        if require_gatekeeper:
            run_gatekeeper_assessment(app_path)
        if require_staple:
            run_staple_validation(app_path)

        return ReleaseVerificationResult(
            version=normalized_version,
            archive_path=archive_path,
            digest=digest,
            extracted_app_path=app_path,
        )
    except Exception:
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify Shorty release artifacts.")
    parser.add_argument("--version", required=True)
    parser.add_argument(
        "--artifact-label",
        help="Artifact label used in the default archive path.",
    )
    parser.add_argument(
        "--archive-path",
        help="Release zip path. Defaults to .build/releases/shorty-VERSION-macos.zip.",
    )
    parser.add_argument(
        "--checksum-path",
        help="Checksum path. Defaults to ARCHIVE.sha256.",
    )
    parser.add_argument("--require-codesign", action="store_true")
    parser.add_argument("--require-gatekeeper", action="store_true")
    parser.add_argument("--require-staple", action="store_true")
    args = parser.parse_args(argv)

    try:
        version = validate_package_version(args.version)
        artifact_label = validate_package_label(args.artifact_label or version, version)
        archive_path = (
            Path(args.archive_path)
            if args.archive_path
            else (DEFAULT_OUTPUT_DIR / f"shorty-{artifact_label}-macos.zip")
        )
        checksum_path = (
            Path(args.checksum_path)
            if args.checksum_path
            else (archive_path.with_name(f"{archive_path.name}.sha256"))
        )
        result = verify_release(
            version=version,
            archive_path=archive_path,
            checksum_path=checksum_path,
            artifact_label=artifact_label,
            require_codesign=args.require_codesign,
            require_gatekeeper=args.require_gatekeeper,
            require_staple=args.require_staple,
        )
    except (
        AppPackageError,
        ReleaseVerificationError,
        SafariExtensionVerificationError,
        subprocess.CalledProcessError,
        zipfile.BadZipFile,
    ) as error:
        print(f"ERROR: {error}")
        return 2

    print(f"Release verified: {result.archive_path}")
    print(f"SHA256: {result.digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
