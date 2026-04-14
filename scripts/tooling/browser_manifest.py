#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

HOST_NAME = "com.shorty.browser_bridge"
CHROME_EXTENSION_ID_PATTERN = re.compile(r"[a-p]{32}")

BROWSER_MANIFEST_RELATIVE_DIRS: dict[str, Path] = {
    "chrome": Path("Library/Application Support/Google/Chrome/NativeMessagingHosts"),
    "chrome-canary": Path(
        "Library/Application Support/Google/Chrome Canary/NativeMessagingHosts"
    ),
    "chromium": Path("Library/Application Support/Chromium/NativeMessagingHosts"),
    "brave": Path(
        "Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
    ),
    "edge": Path("Library/Application Support/Microsoft Edge/NativeMessagingHosts"),
    "vivaldi": Path("Library/Application Support/Vivaldi/NativeMessagingHosts"),
}


class BrowserManifestError(RuntimeError):
    """Raised when a browser native messaging manifest cannot be managed."""


def validate_extension_id(extension_id: str) -> str:
    normalized = extension_id.strip().lower()
    if not CHROME_EXTENSION_ID_PATTERN.fullmatch(normalized):
        raise BrowserManifestError(
            "Chrome extension ID must be 32 lowercase characters from a-p."
        )
    return normalized


def normalize_browser_names(value: str | None) -> list[str]:
    if value is None or not value.strip():
        return ["chrome"]

    names = [part.strip().lower() for part in value.split(",") if part.strip()]
    if names == ["all"]:
        return sorted(BROWSER_MANIFEST_RELATIVE_DIRS)

    unknown = [name for name in names if name not in BROWSER_MANIFEST_RELATIVE_DIRS]
    if unknown:
        formatted = ", ".join(unknown)
        raise BrowserManifestError(f"Unsupported browser target(s): {formatted}")

    return names


def manifest_directories(home: Path, browsers: list[str]) -> list[Path]:
    return [home / BROWSER_MANIFEST_RELATIVE_DIRS[browser] for browser in browsers]


def manifest_path(directory: Path) -> Path:
    return directory / f"{HOST_NAME}.json"


def manifest_payload(extension_id: str, bridge_path: Path) -> dict[str, object]:
    normalized_extension_id = validate_extension_id(extension_id)
    resolved_bridge_path = bridge_path.expanduser().resolve()
    return {
        "name": HOST_NAME,
        "description": "Shorty browser context bridge",
        "path": str(resolved_bridge_path),
        "type": "stdio",
        "allowed_origins": [
            f"chrome-extension://{normalized_extension_id}/",
        ],
    }


def install_manifests(
    extension_id: str,
    bridge_path: Path,
    home: Path,
    browsers: list[str],
) -> list[Path]:
    payload = manifest_payload(extension_id, bridge_path)
    installed: list[Path] = []
    for directory in manifest_directories(home, browsers):
        directory.mkdir(parents=True, exist_ok=True)
        path = manifest_path(directory)
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
        installed.append(path)
    return installed


def uninstall_manifests(home: Path, browsers: list[str]) -> list[Path]:
    removed: list[Path] = []
    for directory in manifest_directories(home, browsers):
        path = manifest_path(directory)
        if path.exists():
            path.unlink()
            removed.append(path)
    return removed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Manage Shorty browser bridge manifests."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    install = subparsers.add_parser(
        "install",
        help="Install native messaging manifests.",
    )
    install.add_argument("--extension-id", required=True)
    install.add_argument("--bridge-path", required=True)
    install.add_argument("--browsers", default="chrome")
    install.add_argument("--home", default=str(Path.home()))

    uninstall = subparsers.add_parser(
        "uninstall",
        help="Remove native messaging manifests.",
    )
    uninstall.add_argument("--browsers", default="chrome")
    uninstall.add_argument("--home", default=str(Path.home()))

    args = parser.parse_args(argv)

    try:
        browsers = normalize_browser_names(args.browsers)
        if args.command == "install":
            paths = install_manifests(
                extension_id=args.extension_id,
                bridge_path=Path(args.bridge_path),
                home=Path(args.home),
                browsers=browsers,
            )
            for path in paths:
                print(f"Installed native messaging manifest: {path}")
        else:
            paths = uninstall_manifests(home=Path(args.home), browsers=browsers)
            if not paths:
                print("No Shorty native messaging manifests were installed.")
            for path in paths:
                print(f"Removed native messaging manifest: {path}")
    except BrowserManifestError as error:
        print(f"ERROR: {error}")
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
