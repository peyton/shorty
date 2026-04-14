#!/usr/bin/env python3

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path

from scripts.tooling.safari_extension_verify import (
    SafariExtensionVerificationError,
    verify_safari_extension,
)
from scripts.tooling.safari_extension_verify import (
    load_plist as load_extension_plist,
)
from scripts.tooling.versioning import (
    VersionError,
    read_app_version,
    validate_app_version,
    validate_apple_build_number,
)

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_APP_STORE_APP_PATH = (
    REPO_ROOT
    / ".DerivedData"
    / "app-store"
    / "Build"
    / "Products"
    / "Release"
    / "ShortyAppStore.app"
)
DEFAULT_APP_STORE_ENTITLEMENTS = (
    REPO_ROOT / "app" / "Shorty" / "ShortyAppStore.entitlements"
)


class AppStoreValidationError(RuntimeError):
    """Raised when the App Store candidate lane is malformed."""


def load_plist(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise AppStoreValidationError(f"Missing plist: {path}")
    with path.open("rb") as file:
        data = plistlib.load(file)
    if not isinstance(data, dict):
        raise AppStoreValidationError(f"Invalid plist: {path}")
    return data


def validate_app_store_candidate(
    app_path: Path,
    entitlements_path: Path = DEFAULT_APP_STORE_ENTITLEMENTS,
    expected_version: str | None = None,
    expected_build_number: str | None = None,
) -> None:
    if not app_path.is_dir():
        raise AppStoreValidationError(f"App Store candidate app not found: {app_path}")

    if expected_version is None:
        expected_version = read_app_version()
    else:
        expected_version = validate_app_version(expected_version)
    if expected_build_number is not None:
        expected_build_number = validate_apple_build_number(expected_build_number)

    info = load_plist(app_path / "Contents" / "Info.plist")
    bundle_id = info.get("CFBundleIdentifier")
    if bundle_id != "app.peyton.shorty.appstore":
        raise AppStoreValidationError(
            "Expected app-store bundle id app.peyton.shorty.appstore, "
            f"found {bundle_id}"
        )
    validate_bundle_version(
        info=info,
        expected_version=expected_version,
        expected_build_number=expected_build_number,
        bundle_name="ShortyAppStore.app",
    )

    entitlements = load_plist(entitlements_path)
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        raise AppStoreValidationError("App Store entitlements must enable App Sandbox.")

    extension = verify_safari_extension(
        app_path=app_path,
        expected_bundle_id="app.peyton.shorty.appstore.SafariWebExtension",
        extension_bundle_name="ShortyAppStoreSafariWebExtension.appex",
        require_codesign=False,
    )
    extension_info = load_extension_plist(
        extension.extension_path / "Contents" / "Info.plist"
    )
    validate_bundle_version(
        info=extension_info,
        expected_version=expected_version,
        expected_build_number=expected_build_number,
        bundle_name="ShortyAppStoreSafariWebExtension.appex",
    )


def validate_bundle_version(
    info: dict[str, object],
    expected_version: str,
    expected_build_number: str | None,
    bundle_name: str,
) -> None:
    version = info.get("CFBundleShortVersionString")
    if version != expected_version:
        raise AppStoreValidationError(
            f"Expected {bundle_name} version {expected_version}, found {version}."
        )

    build_number = info.get("CFBundleVersion")
    if not isinstance(build_number, str):
        raise AppStoreValidationError(
            f"Expected {bundle_name} build number to be a string, found "
            f"{build_number!r}."
        )
    try:
        normalized_build_number = validate_apple_build_number(build_number)
    except VersionError as error:
        raise AppStoreValidationError(
            f"Invalid {bundle_name} build number: {error}"
        ) from error

    if (
        expected_build_number is not None
        and normalized_build_number != expected_build_number
    ):
        raise AppStoreValidationError(
            f"Expected {bundle_name} build number {expected_build_number}, "
            f"found {normalized_build_number}."
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate App Store candidate output.")
    parser.add_argument("--app-path", default=str(DEFAULT_APP_STORE_APP_PATH))
    parser.add_argument("--version")
    parser.add_argument("--build-number")
    parser.add_argument(
        "--entitlements-path",
        default=str(DEFAULT_APP_STORE_ENTITLEMENTS),
    )
    args = parser.parse_args(argv)

    try:
        validate_app_store_candidate(
            app_path=Path(args.app_path),
            entitlements_path=Path(args.entitlements_path),
            expected_version=args.version,
            expected_build_number=args.build_number,
        )
    except (
        AppStoreValidationError,
        SafariExtensionVerificationError,
        VersionError,
    ) as error:
        print(f"ERROR: {error}")
        return 2

    print(f"App Store candidate verified: {args.app_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
