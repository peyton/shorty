#!/usr/bin/env python3
"""Diagnose signing, notarization, and TestFlight environment setup."""

from __future__ import annotations

import os
import platform
import plistlib
import shutil
import subprocess
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

from scripts.tooling.versioning import VersionError, read_app_version

REPO_ROOT = Path(__file__).resolve().parents[2]

ENTITLEMENTS_DIR = REPO_ROOT / "app" / "Shorty"

ENTITLEMENTS_FILES: dict[str, str] = {
    "Shorty.entitlements": "Developer ID signing",
    "ShortySafariWebExtension.entitlements": "Safari extension signing",
    "ShortyAppStore.entitlements": "App Store / TestFlight builds",
}

CI_SECRETS: list[tuple[str, str]] = [
    (
        "SHORTY_DEVELOPER_ID_CERTIFICATE_PEM",
        "Developer ID Application certificate PEM (-----BEGIN CERTIFICATE-----)",
    ),
    (
        "SHORTY_DEVELOPER_ID_PRIVATE_KEY_PEM",
        "Developer ID Application private key PEM",
    ),
    (
        "SHORTY_DEVELOPER_ID_PRIVATE_KEY_PASSWORD",
        "Optional password for encrypted Developer ID private key PEM",
    ),
    (
        "SHORTY_DEVELOPER_ID_APP_PROFILE",
        "Base64 profileContent (recommended) or raw provisioning profile for "
        "app.peyton.shorty",
    ),
    (
        "SHORTY_DEVELOPER_ID_EXTENSION_PROFILE",
        "Base64 profileContent (recommended) or raw provisioning profile for "
        "app.peyton.shorty.SafariWebExtension",
    ),
    (
        "SHORTY_APP_STORE_APP_PROFILE",
        "Base64 profileContent (recommended) or raw provisioning profile for "
        "app.peyton.shorty.appstore",
    ),
    (
        "SHORTY_APP_STORE_EXTENSION_PROFILE",
        "Base64 profileContent (recommended) or raw provisioning profile for "
        "app.peyton.shorty.appstore.SafariWebExtension",
    ),
    (
        "SHORTY_APPLE_DISTRIBUTION_CERTIFICATE_PEM",
        "Optional for manual TestFlight export: Apple Distribution certificate PEM",
    ),
    (
        "SHORTY_APPLE_DISTRIBUTION_PRIVATE_KEY_PEM",
        "Optional for manual TestFlight export: Apple Distribution private key PEM",
    ),
    (
        "SHORTY_APPLE_DISTRIBUTION_PRIVATE_KEY_PASSWORD",
        "Optional password for encrypted Apple Distribution private key PEM",
    ),
    (
        "SHORTY_MAC_INSTALLER_DISTRIBUTION_CERTIFICATE_PEM",
        "Optional for manual TestFlight export: Mac Installer Distribution certificate PEM",
    ),
    (
        "SHORTY_MAC_INSTALLER_DISTRIBUTION_PRIVATE_KEY_PEM",
        "Optional for manual TestFlight export: Mac Installer Distribution private key PEM",
    ),
    (
        "SHORTY_MAC_INSTALLER_DISTRIBUTION_PRIVATE_KEY_PASSWORD",
        "Optional password for encrypted Mac Installer Distribution private key PEM",
    ),
    (
        "SHORTY_CI_KEYCHAIN_PASSWORD",
        "Arbitrary strong password for the CI temp keychain",
    ),
    (
        "SHORTY_CODESIGN_IDENTITY",
        'Full identity, e.g. "Developer ID Application: Name (TEAMID)"',
    ),
    (
        "SHORTY_APP_STORE_CONNECT_API_KEY_P8",
        "Raw .p8 App Store Connect API Team key contents",
    ),
    (
        "SHORTY_APP_STORE_CONNECT_KEY_ID",
        "Key ID from the .p8 filename",
    ),
    (
        "SHORTY_APP_STORE_CONNECT_ISSUER_ID",
        "Issuer UUID from App Store Connect > Keys",
    ),
]


class Status(Enum):
    PASS = "pass"
    FAIL = "fail"
    WARN = "warn"
    SKIP = "skip"


@dataclass(frozen=True)
class CheckResult:
    name: str
    status: Status
    message: str
    fix: str = ""


@dataclass
class DoctorReport:
    sections: list[tuple[str, list[CheckResult]]] = field(default_factory=list)

    def _current(self) -> list[CheckResult]:
        return self.sections[-1][1]

    def begin_section(self, title: str) -> None:
        self.sections.append((title, []))

    def add(self, result: CheckResult) -> None:
        self._current().append(result)

    @property
    def all_checks(self) -> list[CheckResult]:
        return [c for _, checks in self.sections for c in checks]

    @property
    def passed(self) -> bool:
        return all(c.status != Status.FAIL for c in self.all_checks)

    @property
    def failures(self) -> list[CheckResult]:
        return [c for c in self.all_checks if c.status == Status.FAIL]


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------


def check_version_file(repo_root: Path = REPO_ROOT) -> CheckResult:
    version_file = repo_root / "VERSION"
    if not version_file.is_file():
        return CheckResult(
            "VERSION file",
            Status.FAIL,
            "Not found",
            "Create a VERSION file in the repo root with a SemVer version "
            "(e.g. 1.0.0).",
        )
    try:
        version = read_app_version(version_file)
        return CheckResult("VERSION file", Status.PASS, version)
    except VersionError as exc:
        return CheckResult(
            "VERSION file",
            Status.FAIL,
            str(exc),
            "Set a valid MAJOR.MINOR.PATCH version in the VERSION file.",
        )


def check_team_id(env: dict[str, str]) -> CheckResult:
    team_id = env.get("TEAM_ID", "").strip()
    if not team_id:
        return CheckResult(
            "Team ID",
            Status.FAIL,
            "TEAM_ID is not set",
            "Set TEAM_ID or verify scripts/tooling/shorty.env is sourced.",
        )
    return CheckResult("Team ID", Status.PASS, team_id)


def check_xcode() -> CheckResult:
    if platform.system() != "Darwin":
        return CheckResult("Xcode", Status.SKIP, "Not on macOS")

    if not shutil.which("xcodebuild"):
        return CheckResult(
            "Xcode",
            Status.FAIL,
            "xcodebuild not found",
            "Install Xcode from the Mac App Store, then run:\n  xcode-select --install",
        )

    try:
        result = subprocess.run(
            ["xcodebuild", "-version"],
            check=True,
            capture_output=True,
            text=True,
        )
        version_line = result.stdout.strip().split("\n")[0]
        return CheckResult("Xcode", Status.PASS, version_line)
    except subprocess.CalledProcessError:
        return CheckResult(
            "Xcode",
            Status.FAIL,
            "xcodebuild returned an error",
            "Run: xcode-select --install",
        )


def check_entitlement_file(
    name: str,
    purpose: str,
    entitlements_dir: Path = ENTITLEMENTS_DIR,
    repo_root: Path = REPO_ROOT,
) -> CheckResult:
    path = entitlements_dir / name
    if not path.is_file():
        return CheckResult(
            name,
            Status.FAIL,
            f"Missing ({path.relative_to(repo_root)})",
            f"Required for {purpose}.",
        )
    try:
        with path.open("rb") as fh:
            data = plistlib.load(fh)
    except Exception as exc:
        return CheckResult(
            name,
            Status.FAIL,
            f"Cannot parse plist: {exc}",
            f"Fix {path.relative_to(repo_root)} — must be a valid property list.",
        )

    groups = data.get("com.apple.security.application-groups", [])
    if not groups:
        return CheckResult(
            name,
            Status.WARN,
            "No application-groups defined",
            f"Add com.apple.security.application-groups to "
            f"{path.relative_to(repo_root)}.",
        )

    if "AppStore" in name:
        if data.get("com.apple.security.app-sandbox") is not True:
            return CheckResult(
                name,
                Status.FAIL,
                "App Sandbox not enabled",
                f"Set com.apple.security.app-sandbox to true in "
                f"{path.relative_to(repo_root)}.",
            )

    return CheckResult(name, Status.PASS, f"Valid ({', '.join(groups)})")


def check_codesign_identity(env: dict[str, str]) -> CheckResult:
    identity = env.get("SHORTY_CODESIGN_IDENTITY", "").strip()
    if not identity:
        return CheckResult(
            "SHORTY_CODESIGN_IDENTITY",
            Status.FAIL,
            "Not set",
            "Set SHORTY_CODESIGN_IDENTITY to your Developer ID Application "
            "identity.\nRun: security find-identity -v -p codesigning",
        )
    if identity == "-":
        return CheckResult(
            "SHORTY_CODESIGN_IDENTITY",
            Status.WARN,
            'Ad-hoc ("-") — only valid for local testing',
            "For notarized builds set a real Developer ID identity.\n"
            "Run: security find-identity -v -p codesigning",
        )
    return CheckResult("SHORTY_CODESIGN_IDENTITY", Status.PASS, identity)


def check_codesign_keychain(env: dict[str, str]) -> CheckResult:
    if platform.system() != "Darwin":
        return CheckResult("Keychain identity", Status.SKIP, "Not on macOS")

    identity = env.get("SHORTY_CODESIGN_IDENTITY", "").strip()
    if not identity or identity == "-":
        return CheckResult("Keychain identity", Status.SKIP, "No identity to verify")

    try:
        result = subprocess.run(
            ["security", "find-identity", "-v", "-p", "codesigning"],
            check=True,
            capture_output=True,
            text=True,
        )
        if identity in result.stdout:
            return CheckResult("Keychain identity", Status.PASS, "Found in keychain")
        return CheckResult(
            "Keychain identity",
            Status.FAIL,
            f"Not found: {identity}",
            "Import your Developer ID Application certificate:\n"
            "  1. Export .p12 from Keychain Access on a machine that has it\n"
            "  2. security import cert.p12 -P <password> -A\n"
            "  3. Verify: security find-identity -v -p codesigning",
        )
    except subprocess.CalledProcessError, FileNotFoundError:
        return CheckResult("Keychain identity", Status.SKIP, "Could not query keychain")


def check_notarytool() -> CheckResult:
    if platform.system() != "Darwin":
        return CheckResult("notarytool", Status.SKIP, "Not on macOS")

    try:
        subprocess.run(
            ["xcrun", "notarytool", "--help"],
            check=True,
            capture_output=True,
        )
        return CheckResult("notarytool", Status.PASS, "Available")
    except subprocess.CalledProcessError, FileNotFoundError:
        return CheckResult(
            "notarytool",
            Status.FAIL,
            "xcrun notarytool not available",
            "Requires Xcode 13+ with command-line tools installed.",
        )


def check_notarization_credentials(env: dict[str, str]) -> CheckResult:
    profile = env.get("NOTARYTOOL_PROFILE", "").strip()
    if profile:
        return CheckResult(
            "Notarization credentials",
            Status.PASS,
            f"Keychain profile: {profile}",
        )

    key_path = env.get("SHORTY_APP_STORE_CONNECT_KEY_PATH", "").strip()
    api_key_raw = env.get("SHORTY_APP_STORE_CONNECT_API_KEY_P8", "").strip()
    key_id = env.get("SHORTY_APP_STORE_CONNECT_KEY_ID", "").strip()
    issuer_id = env.get("SHORTY_APP_STORE_CONNECT_ISSUER_ID", "").strip()

    missing = []
    if not key_path and not api_key_raw:
        missing.append("SHORTY_APP_STORE_CONNECT_KEY_PATH")
    if not key_id:
        missing.append("SHORTY_APP_STORE_CONNECT_KEY_ID")
    if not issuer_id:
        missing.append("SHORTY_APP_STORE_CONNECT_ISSUER_ID")

    if missing:
        return CheckResult(
            "Notarization credentials",
            Status.FAIL,
            f"Missing: {', '.join(missing)}",
            "Option A — keychain profile (local):\n"
            "  xcrun notarytool store-credentials <profile-name>\n"
            "  export NOTARYTOOL_PROFILE=<profile-name>\n\n"
            "Option B — API key (local and CI):\n"
            "  export SHORTY_APP_STORE_CONNECT_KEY_PATH=/path/to/AuthKey_XXX.p8\n"
            "  # or set SHORTY_APP_STORE_CONNECT_API_KEY_P8 to raw .p8 text\n"
            "  export SHORTY_APP_STORE_CONNECT_KEY_ID=<key-id>\n"
            "  export SHORTY_APP_STORE_CONNECT_ISSUER_ID=<issuer-uuid>\n\n"
            "The API key must be a Team key (not Individual).",
        )

    if key_path and not Path(key_path).is_file():
        return CheckResult(
            "Notarization credentials",
            Status.FAIL,
            f"API key file not found: {key_path}",
            "Verify SHORTY_APP_STORE_CONNECT_KEY_PATH points to a valid .p8 file.",
        )

    source = "file path" if key_path else "raw SHORTY_APP_STORE_CONNECT_API_KEY_P8"
    return CheckResult(
        "Notarization credentials",
        Status.PASS,
        f"API key {key_id} ({source})",
    )


def check_testflight_credentials(env: dict[str, str]) -> CheckResult:
    key_path = env.get("SHORTY_APP_STORE_CONNECT_KEY_PATH", "").strip()
    api_key_raw = env.get("SHORTY_APP_STORE_CONNECT_API_KEY_P8", "").strip()
    key_id = env.get("SHORTY_APP_STORE_CONNECT_KEY_ID", "").strip()
    issuer_id = env.get("SHORTY_APP_STORE_CONNECT_ISSUER_ID", "").strip()
    app_profile_path = env.get("SHORTY_APP_STORE_APP_PROFILE_PATH", "").strip()
    extension_profile_path = env.get(
        "SHORTY_APP_STORE_EXTENSION_PROFILE_PATH", ""
    ).strip()
    app_profile_secret = env.get("SHORTY_APP_STORE_APP_PROFILE", "").strip()
    extension_profile_secret = env.get("SHORTY_APP_STORE_EXTENSION_PROFILE", "").strip()
    allow_local = env.get("SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING") == "1"

    has_profiles = bool(app_profile_path and extension_profile_path) or bool(
        app_profile_secret and extension_profile_secret
    )

    if allow_local and (key_path or api_key_raw) and key_id and issuer_id and has_profiles:
        source = "file path" if key_path else "raw SHORTY_APP_STORE_CONNECT_API_KEY_P8"
        return CheckResult(
            "TestFlight credentials",
            Status.PASS,
            f"API key {key_id} via {source} with local App Store signing enabled",
        )

    if (key_path or api_key_raw) and key_id and issuer_id and has_profiles:
        source = "file path" if key_path else "raw SHORTY_APP_STORE_CONNECT_API_KEY_P8"
        return CheckResult(
            "TestFlight credentials",
            Status.PASS,
            f"API key {key_id} via {source} (App Store profile pair configured)",
        )

    if (key_path or api_key_raw) and key_id and issuer_id:
        source = "file path" if key_path else "raw SHORTY_APP_STORE_CONNECT_API_KEY_P8"
        return CheckResult(
            "TestFlight credentials",
            Status.WARN,
            "API key "
            f"{key_id} via {source} "
            "but App Store provisioning profile pair is missing",
            "Set SHORTY_APP_STORE_APP_PROFILE and "
            "SHORTY_APP_STORE_EXTENSION_PROFILE in CI environments. "
            "Use App Store Connect profileContent base64 payloads. "
            "For manual export signing, also add the "
            "SHORTY_APPLE_DISTRIBUTION_* and "
            "SHORTY_MAC_INSTALLER_DISTRIBUTION_* secrets.",
        )

    if allow_local:
        return CheckResult(
            "TestFlight credentials",
            Status.WARN,
            "SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING=1 — using locally installed "
            "certificates and profiles",
            "Ensure an Apple Distribution certificate and provisioning profiles "
            "for app.peyton.shorty.appstore are installed. "
            "Mac Installer Distribution is also required for exported .pkg "
            "upload lanes.",
        )

    missing = []
    if not key_path and not api_key_raw:
        missing.append("SHORTY_APP_STORE_CONNECT_KEY_PATH")
    if not key_id:
        missing.append("SHORTY_APP_STORE_CONNECT_KEY_ID")
    if not issuer_id:
        missing.append("SHORTY_APP_STORE_CONNECT_ISSUER_ID")

    return CheckResult(
        "TestFlight credentials",
        Status.FAIL,
        f"Missing: {', '.join(missing)}",
        "Set the App Store Connect API key credentials (same ones used for "
        "notarization) and configure SHORTY_APP_STORE_APP_PROFILE plus "
        "SHORTY_APP_STORE_EXTENSION_PROFILE in CI.\n"
        "For resilient CI exports, also configure the optional "
        "SHORTY_APPLE_DISTRIBUTION_* and "
        "SHORTY_MAC_INSTALLER_DISTRIBUTION_* secrets.\n\n"
        "Alternatively, set SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING=1 to use\n"
        "locally installed Apple Distribution certificates and profiles.",
    )


# ---------------------------------------------------------------------------
# Report assembly
# ---------------------------------------------------------------------------


def run_doctor(
    env: dict[str, str] | None = None,
    repo_root: Path = REPO_ROOT,
) -> DoctorReport:
    env = env if env is not None else dict(os.environ)
    report = DoctorReport()
    ent_dir = repo_root / "app" / "Shorty"

    report.begin_section("General")
    report.add(check_version_file(repo_root))
    report.add(check_team_id(env))
    report.add(check_xcode())

    report.begin_section("Entitlements")
    for name, purpose in ENTITLEMENTS_FILES.items():
        report.add(
            check_entitlement_file(
                name, purpose, entitlements_dir=ent_dir, repo_root=repo_root
            )
        )

    report.begin_section("Developer ID Signing")
    report.add(check_codesign_identity(env))
    report.add(check_codesign_keychain(env))

    report.begin_section("Notarization")
    report.add(check_notarytool())
    report.add(check_notarization_credentials(env))

    report.begin_section("TestFlight / App Store")
    report.add(check_testflight_credentials(env))

    return report


# ---------------------------------------------------------------------------
# Terminal formatting
# ---------------------------------------------------------------------------

_STATUS_GLYPHS = {
    Status.PASS: "\033[32m✓\033[0m",
    Status.FAIL: "\033[31m✗\033[0m",
    Status.WARN: "\033[33m!\033[0m",
    Status.SKIP: "\033[90m-\033[0m",
}


def format_report(report: DoctorReport) -> str:
    lines: list[str] = []
    lines.append("")
    lines.append("\033[1mShorty Doctor\033[0m")
    lines.append("")

    for title, checks in report.sections:
        lines.append(f"\033[1m{title}\033[0m")
        for check in checks:
            glyph = _STATUS_GLYPHS[check.status]
            lines.append(f"  {glyph} {check.name:42s} {check.message}")
            if check.fix and check.status in (Status.FAIL, Status.WARN):
                for fix_line in check.fix.split("\n"):
                    lines.append(f"    \033[90m{fix_line}\033[0m")
        lines.append("")

    # CI secrets reference
    lines.append("\033[1mGitHub CI Secrets\033[0m")
    lines.append(
        "  Configure these in the GitHub Environments used by release workflows"
        " (\033[1mpreview-release\033[0m and \033[1mrelease\033[0m):"
    )
    for secret_name, desc in CI_SECRETS:
        lines.append(f"  \033[90m-\033[0m {secret_name}")
        lines.append(f"    \033[90m{desc}\033[0m")
    lines.append("")

    # Summary
    counts = {s: 0 for s in Status}
    for check in report.all_checks:
        counts[check.status] += 1

    parts = []
    if counts[Status.FAIL]:
        parts.append(f"\033[31m{counts[Status.FAIL]} failed\033[0m")
    if counts[Status.WARN]:
        parts.append(f"\033[33m{counts[Status.WARN]} warning(s)\033[0m")
    if counts[Status.PASS]:
        parts.append(f"\033[32m{counts[Status.PASS]} passed\033[0m")
    if counts[Status.SKIP]:
        parts.append(f"\033[90m{counts[Status.SKIP]} skipped\033[0m")
    lines.append(", ".join(parts))
    lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str] | None = None) -> int:
    report = run_doctor()
    print(format_report(report))

    if not report.passed:
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
