#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import plistlib
import subprocess
from dataclasses import dataclass
from pathlib import Path

from scripts.tooling.package_app import DEFAULT_APP_PATH

DEFAULT_EXTENSION_BUNDLE_ID = "app.peyton.shorty.SafariWebExtension"
DEFAULT_EXTENSION_BUNDLE_NAME = "ShortySafariWebExtension.appex"
DEFAULT_APP_GROUP = "group.app.peyton.shorty"
APP_GROUP_ENTITLEMENT = "com.apple.security.application-groups"
SAFARI_EXTENSION_POINT = "com.apple.Safari.web-extension"


class SafariExtensionVerificationError(RuntimeError):
    """Raised when the bundled Safari extension is missing or malformed."""


@dataclass(frozen=True)
class SafariExtensionVerificationResult:
    app_path: Path
    extension_path: Path
    bundle_identifier: str
    manifest_version: int


def safari_extension_path(
    app_path: Path,
    extension_bundle_name: str = DEFAULT_EXTENSION_BUNDLE_NAME,
) -> Path:
    return app_path / "Contents" / "PlugIns" / extension_bundle_name


def load_plist(path: Path) -> dict[str, object]:
    if not path.is_file():
        raise SafariExtensionVerificationError(f"Missing plist: {path}")
    with path.open("rb") as file:
        data = plistlib.load(file)
    if not isinstance(data, dict):
        raise SafariExtensionVerificationError(f"Invalid plist: {path}")
    return data


def require_codesign_verified(path: Path) -> None:
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(path)],
        check=True,
        capture_output=True,
        text=True,
    )


def codesign_entitlements(path: Path) -> dict[str, object]:
    result = subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(path)],
        check=True,
        capture_output=True,
    )
    data = result.stdout.strip()
    if not data:
        raise SafariExtensionVerificationError(
            f"Signed bundle is missing entitlements: {path}"
        )
    entitlements = plistlib.loads(data)
    if not isinstance(entitlements, dict):
        raise SafariExtensionVerificationError(f"Invalid entitlements for {path}")
    return entitlements


def require_app_group_entitlement(
    path: Path,
    app_group: str = DEFAULT_APP_GROUP,
) -> None:
    entitlements = codesign_entitlements(path)
    groups = entitlements.get(APP_GROUP_ENTITLEMENT)
    if not isinstance(groups, list) or app_group not in groups:
        raise SafariExtensionVerificationError(
            f"{path} must include {APP_GROUP_ENTITLEMENT}={app_group}"
        )


def verify_safari_extension(
    app_path: Path,
    expected_bundle_id: str = DEFAULT_EXTENSION_BUNDLE_ID,
    extension_bundle_name: str = DEFAULT_EXTENSION_BUNDLE_NAME,
    require_codesign: bool = False,
) -> SafariExtensionVerificationResult:
    resolved_app_path = app_path.expanduser().resolve()
    if not resolved_app_path.is_dir():
        raise SafariExtensionVerificationError(f"App bundle not found: {app_path}")

    extension_path = safari_extension_path(
        resolved_app_path,
        extension_bundle_name=extension_bundle_name,
    )
    if not extension_path.is_dir():
        raise SafariExtensionVerificationError(
            f"Safari extension bundle not found: {extension_path}"
        )

    info = load_plist(extension_path / "Contents" / "Info.plist")
    bundle_id = info.get("CFBundleIdentifier")
    if bundle_id != expected_bundle_id:
        raise SafariExtensionVerificationError(
            f"Expected Safari extension bundle id {expected_bundle_id}, "
            f"found {bundle_id}"
        )

    extension = info.get("NSExtension")
    if not isinstance(extension, dict):
        raise SafariExtensionVerificationError("Safari extension missing NSExtension.")
    extension_point = extension.get("NSExtensionPointIdentifier")
    if extension_point != SAFARI_EXTENSION_POINT:
        raise SafariExtensionVerificationError(
            f"Expected extension point {SAFARI_EXTENSION_POINT}, "
            f"found {extension_point}"
        )

    manifest_path = extension_path / "Contents" / "Resources" / "manifest.json"
    if not manifest_path.is_file():
        raise SafariExtensionVerificationError(
            f"Safari web extension manifest missing: {manifest_path}"
        )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest_version = manifest.get("manifest_version")
    if manifest_version not in {2, 3}:
        raise SafariExtensionVerificationError(
            f"Unexpected Safari manifest_version: {manifest_version}"
        )

    permissions = set(manifest.get("permissions") or [])
    if "nativeMessaging" not in permissions:
        raise SafariExtensionVerificationError(
            "Safari extension manifest must declare nativeMessaging."
        )
    require_manifest_icons(manifest, manifest_path.parent)

    if require_codesign:
        require_codesign_verified(resolved_app_path)
        require_codesign_verified(extension_path)
        require_app_group_entitlement(resolved_app_path)
        require_app_group_entitlement(extension_path)

    return SafariExtensionVerificationResult(
        app_path=resolved_app_path,
        extension_path=extension_path,
        bundle_identifier=str(bundle_id),
        manifest_version=int(manifest_version),
    )


def require_manifest_icons(manifest: dict[str, object], resources_path: Path) -> None:
    icons = manifest.get("icons")
    if not isinstance(icons, dict) or not icons:
        raise SafariExtensionVerificationError(
            "Safari extension manifest must declare an icons mapping."
        )

    for size, relative_path in icons.items():
        if not isinstance(size, str) or not size.isdigit():
            raise SafariExtensionVerificationError(
                "Safari extension manifest icons keys must be numeric strings."
            )
        if not isinstance(relative_path, str) or not relative_path.strip():
            raise SafariExtensionVerificationError(
                "Safari extension manifest icons values must be non-empty paths."
            )
        icon_path = resources_path / relative_path
        if not icon_path.is_file():
            raise SafariExtensionVerificationError(
                f"Safari extension manifest icon is missing: {icon_path}"
            )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Verify Shorty's Safari extension.")
    parser.add_argument(
        "--app-path",
        default=str(DEFAULT_APP_PATH),
        help="Built Shorty.app path.",
    )
    parser.add_argument(
        "--bundle-id",
        default=DEFAULT_EXTENSION_BUNDLE_ID,
        help="Expected Safari extension bundle identifier.",
    )
    parser.add_argument(
        "--extension-bundle-name",
        default=DEFAULT_EXTENSION_BUNDLE_NAME,
        help="Expected appex directory name under Contents/PlugIns.",
    )
    parser.add_argument(
        "--require-codesign",
        action="store_true",
        help="Require codesign verification of the app and extension.",
    )
    args = parser.parse_args(argv)

    try:
        result = verify_safari_extension(
            app_path=Path(args.app_path),
            expected_bundle_id=args.bundle_id,
            extension_bundle_name=args.extension_bundle_name,
            require_codesign=args.require_codesign,
        )
    except (SafariExtensionVerificationError, subprocess.CalledProcessError) as error:
        print(f"ERROR: {error}")
        return 2

    print(f"Safari extension verified: {result.extension_path}")
    print(f"Bundle ID: {result.bundle_identifier}")
    print(f"Manifest version: {result.manifest_version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
