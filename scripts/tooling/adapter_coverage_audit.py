from __future__ import annotations

import argparse
import json
import plistlib
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ADAPTER_REGISTRY = REPO_ROOT / "app/Shorty/Sources/ShortyCore/AdapterRegistry.swift"


def builtin_adapter_ids() -> set[str]:
    source = ADAPTER_REGISTRY.read_text(encoding="utf-8")
    return set(re.findall(r'adapter\(\s*"([^"]+)"', source))


def installed_apps(paths: list[Path]) -> list[dict[str, str]]:
    apps: list[dict[str, str]] = []
    for root in paths:
        if not root.exists():
            continue
        for app in root.glob("*.app"):
            plist = app / "Contents/Info.plist"
            if not plist.exists():
                continue
            try:
                payload = plistlib.loads(plist.read_bytes())
            except Exception:
                continue
            bundle_id = payload.get("CFBundleIdentifier")
            name = (
                payload.get("CFBundleDisplayName")
                or payload.get("CFBundleName")
                or app.stem
            )
            if isinstance(bundle_id, str) and isinstance(name, str):
                apps.append({"bundle_id": bundle_id, "name": name, "path": str(app)})
    return sorted(apps, key=lambda item: item["name"].lower())


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Report installed macOS apps that do not have a Shorty adapter."
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=50,
        help="Maximum missing apps to print in text mode.",
    )
    args = parser.parse_args()

    covered = builtin_adapter_ids()
    roots = [Path("/Applications"), Path.home() / "Applications"]
    apps = installed_apps(roots)
    missing = [app for app in apps if app["bundle_id"] not in covered]
    result = {
        "adapter_count": len(covered),
        "installed_app_count": len(apps),
        "missing_adapter_count": len(missing),
        "missing": missing,
    }

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return

    print(f"Adapters: {len(covered)}")
    print(f"Installed apps scanned: {len(apps)}")
    print(f"Apps without adapters: {len(missing)}")
    for app in missing[: args.limit]:
        print(f"- {app['name']} ({app['bundle_id']})")


if __name__ == "__main__":
    main()
