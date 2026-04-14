#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import plistlib
import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from scripts.tooling.package_app import (
    DEFAULT_APP_PATH,
    REPO_ROOT,
    AppPackageError,
    validate_package_version,
)

PROJECT_FILE = REPO_ROOT / "app" / "Shorty" / "Project.swift"


class ReleasePreflightError(RuntimeError):
    """Raised when release preflight detects a blocker."""


@dataclass(frozen=True)
class ReleasePreflightResult:
    version: str
    project_version: str
    app_version: str


def project_marketing_version(project_file: Path = PROJECT_FILE) -> str:
    text = project_file.read_text(encoding="utf-8")
    match = re.search(r'let\s+marketingVersion\s*=\s*"([^"]+)"', text)
    if not match:
        raise ReleasePreflightError(
            f"Could not find marketingVersion in {project_file}"
        )
    return match.group(1)


def app_bundle_version(app_path: Path) -> str:
    info_plist = app_path / "Contents" / "Info.plist"
    if not info_plist.is_file():
        raise ReleasePreflightError(f"Built app not found at {app_path}")

    with info_plist.open("rb") as file:
        info = plistlib.load(file)

    version = info.get("CFBundleShortVersionString")
    if not isinstance(version, str) or not version.strip():
        raise ReleasePreflightError(
            f"CFBundleShortVersionString missing in {info_plist}"
        )
    return version


def git_status_short(repo_root: Path = REPO_ROOT) -> str:
    result = subprocess.run(
        ["git", "status", "--short"],
        cwd=repo_root,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def xcode_version_text() -> str:
    result = subprocess.run(
        ["xcodebuild", "-version"],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.strip()


def check_xcode_is_stable(version_text: str, allow_beta: bool) -> None:
    if allow_beta:
        return
    if "beta" in version_text.lower():
        raise ReleasePreflightError(
            "Public releases must use a stable Xcode. Set SHORTY_ALLOW_BETA_XCODE=1 "
            "only for internal testing."
        )


def check_signing_identity(env: dict[str, str]) -> None:
    identity = env.get("SHORTY_CODESIGN_IDENTITY", "").strip()
    allow_ad_hoc = env.get("SHORTY_ALLOW_AD_HOC_RELEASE") == "1"
    if identity and identity != "-":
        return
    if allow_ad_hoc:
        return
    raise ReleasePreflightError(
        "SHORTY_CODESIGN_IDENTITY must name a Developer ID Application identity "
        "for public release preflight."
    )


def run_preflight(
    version: str,
    app_path: Path,
    env: dict[str, str] | None = None,
    repo_root: Path = REPO_ROOT,
) -> ReleasePreflightResult:
    env = env or dict(os.environ)
    normalized_version = validate_package_version(version)

    dirty = git_status_short(repo_root)
    if dirty and env.get("SHORTY_ALLOW_DIRTY_RELEASE") != "1":
        raise ReleasePreflightError(
            "Release preflight requires a clean git working tree."
        )

    project_version = project_marketing_version()
    if project_version != normalized_version:
        raise ReleasePreflightError(
            f"Requested version {normalized_version} does not match Project.swift "
            f"marketingVersion {project_version}."
        )

    app_version = app_bundle_version(app_path)
    if app_version != normalized_version:
        raise ReleasePreflightError(
            f"Requested version {normalized_version} does not match built app "
            f"version {app_version}."
        )

    check_xcode_is_stable(
        xcode_version_text(),
        allow_beta=env.get("SHORTY_ALLOW_BETA_XCODE") == "1",
    )
    check_signing_identity(env)

    return ReleasePreflightResult(
        version=normalized_version,
        project_version=project_version,
        app_version=app_version,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run Shorty release preflight checks.")
    parser.add_argument("--version", required=True, help="Release version label.")
    parser.add_argument(
        "--app-path",
        default=str(DEFAULT_APP_PATH),
        help="Built Shorty.app path.",
    )
    args = parser.parse_args(argv)

    try:
        result = run_preflight(version=args.version, app_path=Path(args.app_path))
    except (ReleasePreflightError, AppPackageError) as error:
        print(f"ERROR: {error}")
        return 2

    print(f"Release preflight passed for Shorty {result.version}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
