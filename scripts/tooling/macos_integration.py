#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

from scripts.tooling.macos_fixture import (
    DEFAULT_OUTPUT_DIR,
    FIXTURE_BUNDLE_ID,
    MacOSFixtureError,
    build_fixture_bundle,
)


class MacOSIntegrationError(RuntimeError):
    """Raised when a macOS automation integration check fails."""


def run_automation_probe(
    app_path: Path,
    probe_path: Path,
    *,
    require_ui_scripting: bool,
) -> None:
    command = [str(probe_path), str(app_path), FIXTURE_BUNDLE_ID]
    if require_ui_scripting:
        command.append("--require-ui-scripting")

    try:
        subprocess.run(command, check=True)
    except subprocess.CalledProcessError as error:
        raise MacOSIntegrationError(
            f"macOS automation probe failed with exit code {error.returncode}."
        ) from error


def run_macos_integration(
    output_dir: Path = DEFAULT_OUTPUT_DIR,
    *,
    require_ui_scripting: bool = False,
) -> None:
    result = build_fixture_bundle(output_dir)
    print(f"Built fixture app: {result.app_path}", flush=True)
    print(f"Built automation probe: {result.probe_path}", flush=True)
    run_automation_probe(
        result.app_path,
        result.probe_path,
        require_ui_scripting=require_ui_scripting,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Build and exercise Shorty's macOS integration fixture."
    )
    parser.add_argument(
        "--output-dir",
        default=str(DEFAULT_OUTPUT_DIR),
        help="Directory for generated fixture artifacts.",
    )
    parser.add_argument(
        "--require-ui-scripting",
        action="store_true",
        default=os.environ.get("SHORTY_REQUIRE_UI_AUTOMATION") == "1",
        help="Fail if Accessibility-backed menu inspection is unavailable.",
    )
    args = parser.parse_args(argv)

    try:
        run_macos_integration(
            output_dir=Path(args.output_dir),
            require_ui_scripting=args.require_ui_scripting,
        )
    except (MacOSFixtureError, MacOSIntegrationError) as error:
        print(f"ERROR: {error}")
        return 2

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
