#!/usr/bin/env python3

from __future__ import annotations

import argparse
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_VERSION_FILE = REPO_ROOT / "VERSION"

APP_VERSION_PATTERN = re.compile(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")
APPLE_BUILD_NUMBER_PATTERN = re.compile(r"[1-9][0-9]*")
PREVIEW_LABEL_PATTERN = re.compile(r"preview-[A-Za-z0-9][A-Za-z0-9._-]*")
GIT_SHA_PATTERN = re.compile(r"[0-9a-fA-F]{12,40}")


class VersionError(ValueError):
    """Raised when release version metadata is invalid."""


def validate_app_version(version: str) -> str:
    normalized = version.strip()
    if not APP_VERSION_PATTERN.fullmatch(normalized):
        raise VersionError(
            "App version must be strict MAJOR.MINOR.PATCH SemVer, "
            f"received {version!r}."
        )
    return normalized


def read_app_version(version_file: Path = DEFAULT_VERSION_FILE) -> str:
    if not version_file.is_file():
        raise VersionError(f"Version file not found: {version_file}")
    return validate_app_version(version_file.read_text(encoding="utf-8"))


def validate_apple_build_number(build_number: str) -> str:
    normalized = build_number.strip()
    if not APPLE_BUILD_NUMBER_PATTERN.fullmatch(normalized):
        raise VersionError(
            "Apple build number must be a positive numeric string, "
            f"received {build_number!r}."
        )
    return normalized


def preview_label_for_sha(sha: str) -> str:
    normalized = sha.strip().lower()
    if not GIT_SHA_PATTERN.fullmatch(normalized):
        raise VersionError(
            "Preview labels require a 12- to 40-character hexadecimal git SHA, "
            f"received {sha!r}."
        )
    return f"preview-{normalized[:12]}"


def validate_preview_label(label: str) -> str:
    normalized = label.strip()
    if not PREVIEW_LABEL_PATTERN.fullmatch(normalized):
        raise VersionError(
            "Preview artifact labels must start with 'preview-' and contain only "
            f"letters, numbers, dots, underscores, or hyphens; received {label!r}."
        )
    return normalized


def validate_artifact_label(label: str, app_version: str) -> str:
    normalized_version = validate_app_version(app_version)
    normalized_label = label.strip()
    if normalized_label == normalized_version:
        return normalized_label
    return validate_preview_label(normalized_label)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate Shorty release versions.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    app_version_parser = subparsers.add_parser("app-version")
    app_version_parser.add_argument("--version")

    build_number_parser = subparsers.add_parser("build-number")
    build_number_parser.add_argument("--build-number", required=True)

    artifact_label_parser = subparsers.add_parser("artifact-label")
    artifact_label_parser.add_argument("--label", required=True)
    artifact_label_parser.add_argument("--app-version", required=True)

    preview_label_parser = subparsers.add_parser("preview-label")
    preview_label_parser.add_argument("--sha", required=True)

    args = parser.parse_args(argv)

    try:
        if args.command == "app-version":
            value = (
                validate_app_version(args.version)
                if args.version
                else read_app_version()
            )
        elif args.command == "build-number":
            value = validate_apple_build_number(args.build_number)
        elif args.command == "artifact-label":
            value = validate_artifact_label(args.label, args.app_version)
        elif args.command == "preview-label":
            value = preview_label_for_sha(args.sha)
        else:
            parser.error(f"Unknown command: {args.command}")
    except VersionError as error:
        print(f"ERROR: {error}")
        return 2

    print(value)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
