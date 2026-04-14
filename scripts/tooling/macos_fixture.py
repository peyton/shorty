#!/usr/bin/env python3

from __future__ import annotations

import plistlib
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
MACOS_FIXTURE_ROOT = REPO_ROOT / "tests" / "fixtures" / "macos"
FIXTURE_SOURCE = MACOS_FIXTURE_ROOT / "ShortcutFixtureEditor.swift"
PROBE_SOURCE = MACOS_FIXTURE_ROOT / "AutomationProbe.swift"
DEFAULT_OUTPUT_DIR = REPO_ROOT / ".build" / "fixtures" / "macos"

FIXTURE_APP_NAME = "ShortyFixtureEditor"
FIXTURE_EXECUTABLE_NAME = "ShortyFixtureEditor"
FIXTURE_BUNDLE_ID = "app.peyton.shorty.fixture.editor"
PROBE_EXECUTABLE_NAME = "AutomationProbe"


class MacOSFixtureError(RuntimeError):
    """Raised when a macOS integration fixture cannot be built."""


@dataclass(frozen=True)
class FixtureBuildResult:
    app_path: Path
    executable_path: Path
    probe_path: Path


def fixture_info_plist() -> dict[str, object]:
    return {
        "CFBundleDevelopmentRegion": "en",
        "CFBundleExecutable": FIXTURE_EXECUTABLE_NAME,
        "CFBundleIdentifier": FIXTURE_BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": FIXTURE_APP_NAME,
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "13.0",
        "NSPrincipalClass": "NSApplication",
    }


def build_fixture_bundle(output_dir: Path = DEFAULT_OUTPUT_DIR) -> FixtureBuildResult:
    require_macos()
    require_source(FIXTURE_SOURCE)
    require_source(PROBE_SOURCE)
    require_tool("xcrun")

    app_path = output_dir / f"{FIXTURE_APP_NAME}.app"
    contents_dir = app_path / "Contents"
    macos_dir = contents_dir / "MacOS"
    executable_path = macos_dir / FIXTURE_EXECUTABLE_NAME
    probe_path = output_dir / PROBE_EXECUTABLE_NAME

    if app_path.exists():
        shutil.rmtree(app_path)
    output_dir.mkdir(parents=True, exist_ok=True)
    macos_dir.mkdir(parents=True, exist_ok=True)

    compile_swift(FIXTURE_SOURCE, executable_path)
    executable_path.chmod(0o755)
    (contents_dir / "Info.plist").write_bytes(plistlib.dumps(fixture_info_plist()))
    (contents_dir / "PkgInfo").write_text("APPL????", encoding="ascii")

    compile_swift(PROBE_SOURCE, probe_path)
    probe_path.chmod(0o755)

    return FixtureBuildResult(
        app_path=app_path,
        executable_path=executable_path,
        probe_path=probe_path,
    )


def compile_swift(source: Path, output: Path) -> None:
    command = [
        "xcrun",
        "swiftc",
        str(source),
        "-o",
        str(output),
        "-framework",
        "AppKit",
        "-framework",
        "ApplicationServices",
    ]
    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as error:
        raise MacOSFixtureError(
            f"Failed to compile {source.relative_to(REPO_ROOT)}."
        ) from error


def require_macos() -> None:
    if sys.platform != "darwin":
        raise MacOSFixtureError("macOS integration fixtures require macOS.")


def require_source(path: Path) -> None:
    if not path.is_file():
        raise MacOSFixtureError(f"Missing fixture source: {path}")


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        raise MacOSFixtureError(f"Required tool is not available on PATH: {name}")
