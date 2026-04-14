from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from scripts.tooling.macos_fixture import (
    FIXTURE_BUNDLE_ID,
    FIXTURE_EXECUTABLE_NAME,
    PROBE_EXECUTABLE_NAME,
    FixtureBuildResult,
    MacOSFixtureError,
    build_fixture_bundle,
    fixture_info_plist,
)
from scripts.tooling.macos_integration import run_automation_probe


def test_fixture_info_plist_declares_launchable_app_bundle() -> None:
    info = fixture_info_plist()

    assert info["CFBundlePackageType"] == "APPL"
    assert info["CFBundleIdentifier"] == FIXTURE_BUNDLE_ID
    assert info["CFBundleExecutable"] == FIXTURE_EXECUTABLE_NAME
    assert info["LSMinimumSystemVersion"] == "13.0"


def test_fixture_build_writes_expected_bundle_layout(tmp_path: Path) -> None:
    def fake_compile(source: Path, output: Path) -> None:
        output.write_text(f"compiled from {source.name}\n", encoding="utf-8")

    with (
        patch("scripts.tooling.macos_fixture.require_macos"),
        patch("scripts.tooling.macos_fixture.require_tool"),
        patch("scripts.tooling.macos_fixture.compile_swift", side_effect=fake_compile),
    ):
        result = build_fixture_bundle(tmp_path)

    assert result == FixtureBuildResult(
        app_path=tmp_path / "ShortyFixtureEditor.app",
        executable_path=tmp_path
        / "ShortyFixtureEditor.app"
        / "Contents"
        / "MacOS"
        / FIXTURE_EXECUTABLE_NAME,
        probe_path=tmp_path / PROBE_EXECUTABLE_NAME,
    )
    assert result.executable_path.read_text(encoding="utf-8").startswith("compiled")
    assert (result.app_path / "Contents" / "Info.plist").is_file()
    assert (result.app_path / "Contents" / "PkgInfo").read_text(
        encoding="ascii"
    ) == "APPL????"
    assert result.probe_path.is_file()


def test_fixture_build_rejects_non_macos() -> None:
    with (
        patch("scripts.tooling.macos_fixture.sys.platform", "linux"),
        pytest.raises(MacOSFixtureError, match="require macOS"),
    ):
        build_fixture_bundle()


def test_automation_probe_includes_strict_ui_scripting_flag(tmp_path: Path) -> None:
    app_path = tmp_path / "ShortyFixtureEditor.app"
    probe_path = tmp_path / "AutomationProbe"

    with patch("scripts.tooling.macos_integration.subprocess.run") as run:
        run_automation_probe(app_path, probe_path, require_ui_scripting=True)

    run.assert_called_once_with(
        [
            str(probe_path),
            str(app_path),
            FIXTURE_BUNDLE_ID,
            "--require-ui-scripting",
        ],
        check=True,
    )
