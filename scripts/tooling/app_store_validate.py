#!/usr/bin/env python3

from __future__ import annotations

import argparse
import plistlib
from pathlib import Path

from scripts.tooling.safari_extension_verify import verify_safari_extension

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
) -> None:
    if not app_path.is_dir():
        raise AppStoreValidationError(f"App Store candidate app not found: {app_path}")

    info = load_plist(app_path / "Contents" / "Info.plist")
    bundle_id = info.get("CFBundleIdentifier")
    if bundle_id != "app.peyton.shorty.appstore":
        raise AppStoreValidationError(
            "Expected app-store bundle id app.peyton.shorty.appstore, "
            f"found {bundle_id}"
        )

    entitlements = load_plist(entitlements_path)
    if entitlements.get("com.apple.security.app-sandbox") is not True:
        raise AppStoreValidationError("App Store entitlements must enable App Sandbox.")

    verify_safari_extension(
        app_path=app_path,
        expected_bundle_id="app.peyton.shorty.appstore.SafariWebExtension",
        extension_bundle_name="ShortyAppStoreSafariWebExtension.appex",
        require_codesign=False,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Validate App Store candidate output.")
    parser.add_argument("--app-path", default=str(DEFAULT_APP_STORE_APP_PATH))
    parser.add_argument(
        "--entitlements-path",
        default=str(DEFAULT_APP_STORE_ENTITLEMENTS),
    )
    args = parser.parse_args(argv)

    try:
        validate_app_store_candidate(
            app_path=Path(args.app_path),
            entitlements_path=Path(args.entitlements_path),
        )
    except AppStoreValidationError as error:
        print(f"ERROR: {error}")
        return 2

    print(f"App Store candidate verified: {args.app_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
