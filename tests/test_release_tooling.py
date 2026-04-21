from __future__ import annotations

import json
import plistlib
import subprocess
import tarfile
import zipfile
from pathlib import Path

import pytest

from scripts.tooling.app_store_validate import (
    AppStoreValidationError,
    validate_app_store_candidate,
)
from scripts.tooling.appcast_generate import AppcastGenerateError, generate_appcast
from scripts.tooling.browser_manifest import (
    HOST_NAME,
    BrowserManifestError,
    install_manifests,
    manifest_payload,
    normalize_browser_names,
    uninstall_manifests,
    validate_extension_id,
)
from scripts.tooling.doctor import (
    CheckResult,
    DoctorReport,
    Status,
    check_codesign_identity,
    check_entitlement_file,
    check_notarization_credentials,
    check_team_id,
    check_testflight_credentials,
    check_version_file,
    format_report,
    run_doctor,
)
from scripts.tooling.legal_resources import (
    LegalResourceError,
    validate_bundled_legal_resources,
    validate_root_legal_resources,
)
from scripts.tooling.package_app import (
    AppPackageError,
    package_app,
    sha256_file,
)
from scripts.tooling.release_preflight import (
    ReleasePreflightError,
    check_signing_identity,
    check_xcode_is_stable,
)
from scripts.tooling.release_verify import verify_release
from scripts.tooling.safari_extension_verify import (
    SafariExtensionVerificationError,
    verify_safari_extension,
)
from scripts.tooling.source_package import package_source
from scripts.tooling.versioning import (
    VersionError,
    preview_label_for_sha,
    validate_app_version,
    validate_apple_build_number,
    validate_artifact_label,
)


def make_fake_app(
    root: Path,
    version: str = "1.0.0",
    build_number: str = "1",
    category: str = "public.app-category.productivity",
    uses_non_exempt_encryption: bool = False,
) -> Path:
    app = root / "Shorty.app"
    contents = app / "Contents"
    macos = contents / "MacOS"
    macos.mkdir(parents=True)
    (macos / "Shorty").write_text("#!/bin/sh\n", encoding="utf-8")
    (contents / "Info.plist").write_bytes(
        plistlib.dumps(
            {
                "CFBundleExecutable": "Shorty",
                "CFBundleIdentifier": "app.peyton.shorty",
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build_number,
                "ITSAppUsesNonExemptEncryption": uses_non_exempt_encryption,
                "LSApplicationCategoryType": category,
            }
        )
    )
    return app


def add_fake_safari_extension(
    app: Path,
    bundle_name: str = "ShortySafariWebExtension.appex",
    bundle_id: str = "app.peyton.shorty.SafariWebExtension",
    version: str = "1.0.0",
    build_number: str = "1",
) -> Path:
    extension = app / "Contents" / "PlugIns" / bundle_name
    resources = extension / "Contents" / "Resources"
    resources.mkdir(parents=True)
    (extension / "Contents" / "MacOS").mkdir()
    (extension / "Contents" / "Info.plist").write_bytes(
        plistlib.dumps(
            {
                "CFBundleExecutable": "ShortySafariWebExtension",
                "CFBundleIdentifier": bundle_id,
                "CFBundleShortVersionString": version,
                "CFBundleVersion": build_number,
                "NSExtension": {
                    "NSExtensionPointIdentifier": "com.apple.Safari.web-extension",
                    "NSExtensionPrincipalClass": (
                        "ShortySafariWebExtension.SafariWebExtensionHandler"
                    ),
                },
            }
        )
    )
    (resources / "manifest.json").write_text(
        (
            '{"manifest_version":3,"permissions":["nativeMessaging"],'
            '"icons":{"16":"icon-16.png","48":"icon-48.png","128":"icon-128.png"},'
            '"background":{"service_worker":"background.js"}}\n'
        ),
        encoding="utf-8",
    )
    for name in ("icon-16.png", "icon-48.png", "icon-128.png"):
        (resources / name).write_bytes(b"png")
    return extension


def test_versioning_validates_semver_build_numbers_and_preview_labels() -> None:
    assert validate_app_version("1.0.0") == "1.0.0"
    assert validate_apple_build_number("123") == "123"
    assert (
        preview_label_for_sha("ABCDEF0123456789abcdef0123456789abcdef01")
        == "preview-abcdef012345"
    )
    assert validate_artifact_label("preview-test", "1.0.0") == "preview-test"

    with pytest.raises(VersionError, match="MAJOR.MINOR.PATCH"):
        validate_app_version("1.0.0-preview")
    with pytest.raises(VersionError, match="positive numeric"):
        validate_apple_build_number("0")
    with pytest.raises(VersionError, match="Preview artifact labels"):
        validate_artifact_label("nightly", "1.0.0")


def add_fake_legal_resources(app: Path) -> Path:
    legal = app / "Contents" / "Resources" / "Legal"
    legal.mkdir(parents=True)
    (legal / "LICENSE.txt").write_text(
        "GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3\n",
        encoding="utf-8",
    )
    (legal / "NOTICE.txt").write_text(
        ("AGPL-3.0-or-later\nhttps://github.com/peyton/shorty\nWITHOUT ANY WARRANTY\n"),
        encoding="utf-8",
    )
    (legal / "THIRD_PARTY_NOTICES.md").write_text(
        "Shorty has no third-party runtime libraries.\n",
        encoding="utf-8",
    )
    return legal


def test_app_package_creates_deterministic_zip_and_checksum(tmp_path: Path) -> None:
    app = make_fake_app(tmp_path)
    output_dir = tmp_path / "releases"

    first = package_app(app, "1.0.0", output_dir)
    second = package_app(app, "1.0.0", output_dir)

    assert first.archive_path == output_dir / "shorty-1.0.0-macos.zip"
    assert first.checksum_path == output_dir / "shorty-1.0.0-macos.zip.sha256"
    assert first.digest == second.digest == sha256_file(first.archive_path)
    assert (
        first.checksum_path.read_text(encoding="utf-8")
        == f"{first.digest}  shorty-1.0.0-macos.zip\n"
    )

    with zipfile.ZipFile(first.archive_path) as archive:
        assert "Shorty.app/" in archive.namelist()
        assert "Shorty.app/Contents/Info.plist" in archive.namelist()


def test_app_package_uses_preview_artifact_label_without_changing_bundle(
    tmp_path: Path,
) -> None:
    app = make_fake_app(tmp_path, version="1.0.0", build_number="123")

    result = package_app(
        app,
        "1.0.0",
        tmp_path / "releases",
        artifact_label="preview-test",
    )

    assert result.archive_path.name == "shorty-preview-test-macos.zip"
    assert result.checksum_path.name == "shorty-preview-test-macos.zip.sha256"
    with zipfile.ZipFile(result.archive_path) as archive:
        info = plistlib.loads(archive.read("Shorty.app/Contents/Info.plist"))
    assert info["CFBundleShortVersionString"] == "1.0.0"
    assert info["CFBundleVersion"] == "123"


def test_app_package_rejects_version_mismatch(tmp_path: Path) -> None:
    app = make_fake_app(tmp_path, version="1.0.0")

    with pytest.raises(AppPackageError, match="does not match app bundle"):
        package_app(app, "2.0.0", tmp_path / "releases")


def test_app_package_preserves_symlink_metadata(tmp_path: Path) -> None:
    app = make_fake_app(tmp_path)
    framework = app / "Contents" / "Frameworks" / "Example.framework"
    version = framework / "Versions" / "A"
    version.mkdir(parents=True)
    (version / "Resources").mkdir()
    (version / "Example").write_text("binary", encoding="utf-8")
    (framework / "Example").symlink_to("Versions/A/Example")
    (framework / "Resources").symlink_to("Versions/Current/Resources")
    (framework / "Versions" / "Current").symlink_to("A")

    result = package_app(app, "1.0.0", tmp_path / "releases")

    with zipfile.ZipFile(result.archive_path) as archive:
        assert_zip_entry_is_symlink(
            archive,
            "Shorty.app/Contents/Frameworks/Example.framework/Example",
            "Versions/A/Example",
        )
        assert_zip_entry_is_symlink(
            archive,
            "Shorty.app/Contents/Frameworks/Example.framework/Resources",
            "Versions/Current/Resources",
        )
        assert_zip_entry_is_symlink(
            archive,
            "Shorty.app/Contents/Frameworks/Example.framework/Versions/Current",
            "A",
        )


def assert_zip_entry_is_symlink(
    archive: zipfile.ZipFile,
    name: str,
    target: str,
) -> None:
    info = archive.getinfo(name)
    file_type = (info.external_attr >> 16) & 0o170000
    assert info.create_system == 3
    assert file_type == 0o120000
    assert archive.read(info).decode("utf-8") == target


def test_release_preflight_rejects_beta_xcode_without_override() -> None:
    with pytest.raises(ReleasePreflightError, match="stable Xcode"):
        check_xcode_is_stable(
            "Xcode 26.5\nBuild version 17F5012f",
            False,
            developer_dir="/Applications/Xcode-26.5.0-Beta.app/Contents/Developer",
        )

    check_xcode_is_stable("Xcode 26.5\nBuild version 17F5012f Beta", True)


def test_release_preflight_requires_real_signing_identity() -> None:
    with pytest.raises(ReleasePreflightError, match="SHORTY_CODESIGN_IDENTITY"):
        check_signing_identity({})

    check_signing_identity(
        {"SHORTY_CODESIGN_IDENTITY": "Developer ID Application: Test"}
    )
    check_signing_identity(
        {
            "SHORTY_CODESIGN_IDENTITY": "-",
            "SHORTY_ALLOW_AD_HOC_RELEASE": "1",
        }
    )


def test_browser_manifest_validates_extension_id() -> None:
    valid = "abcdefghijklmnopabcdefghijklmnop"
    assert validate_extension_id(valid.upper()) == valid

    with pytest.raises(BrowserManifestError, match="extension ID"):
        validate_extension_id("not-a-real-extension")


def test_browser_manifest_installs_and_uninstalls_multiple_browsers(
    tmp_path: Path,
) -> None:
    extension_id = "abcdefghijklmnopabcdefghijklmnop"
    bridge_path = tmp_path / "shorty-bridge"
    bridge_path.write_text("#!/bin/sh\n", encoding="utf-8")
    browsers = normalize_browser_names("chrome,brave,edge")

    installed = install_manifests(extension_id, bridge_path, tmp_path, browsers)

    assert len(installed) == 3
    for path in installed:
        data = path.read_text(encoding="utf-8")
        assert HOST_NAME in data
        assert f"chrome-extension://{extension_id}/" in data

    removed = uninstall_manifests(tmp_path, browsers)
    assert sorted(removed) == sorted(installed)
    assert all(not path.exists() for path in installed)


def test_browser_manifest_payload_uses_resolved_bridge_path(tmp_path: Path) -> None:
    extension_id = "abcdefghijklmnopabcdefghijklmnop"
    bridge_path = tmp_path / "shorty-bridge"
    bridge_path.write_text("#!/bin/sh\n", encoding="utf-8")

    payload = manifest_payload(extension_id, bridge_path)

    assert payload["path"] == str(bridge_path.resolve())
    assert payload["allowed_origins"] == [f"chrome-extension://{extension_id}/"]


def test_safari_extension_verify_requires_bundled_extension(tmp_path: Path) -> None:
    app = make_fake_app(tmp_path)
    extension = add_fake_safari_extension(app)

    result = verify_safari_extension(app, require_codesign=False)

    assert result.extension_path == extension
    assert result.bundle_identifier == "app.peyton.shorty.SafariWebExtension"
    assert result.manifest_version == 3


def test_safari_extension_verify_requires_app_group_entitlements(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    app = make_fake_app(tmp_path)
    add_fake_safari_extension(app)

    def fake_run(
        args: list[str],
        check: bool,
        capture_output: bool,
        text: bool = False,
    ) -> subprocess.CompletedProcess[str] | subprocess.CompletedProcess[bytes]:
        if "--entitlements" in args:
            return subprocess.CompletedProcess(
                args,
                0,
                stdout=plistlib.dumps({}),
                stderr=b"",
            )
        return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    with pytest.raises(SafariExtensionVerificationError, match="application-groups"):
        verify_safari_extension(app, require_codesign=True)


def test_safari_extension_verify_accepts_app_group_entitlements(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    app = make_fake_app(tmp_path)
    add_fake_safari_extension(app)
    entitlement_data = plistlib.dumps(
        {"com.apple.security.application-groups": ["group.app.peyton.shorty"]}
    )

    def fake_run(
        args: list[str],
        check: bool,
        capture_output: bool,
        text: bool = False,
    ) -> subprocess.CompletedProcess[str] | subprocess.CompletedProcess[bytes]:
        if "--entitlements" in args:
            return subprocess.CompletedProcess(
                args,
                0,
                stdout=entitlement_data,
                stderr=b"",
            )
        return subprocess.CompletedProcess(args, 0, stdout="", stderr="")

    monkeypatch.setattr(subprocess, "run", fake_run)

    result = verify_safari_extension(app, require_codesign=True)

    assert result.bundle_identifier == "app.peyton.shorty.SafariWebExtension"


def test_safari_extension_verify_rejects_missing_manifest_icons(tmp_path: Path) -> None:
    app = make_fake_app(tmp_path)
    add_fake_safari_extension(app)
    manifest_path = (
        app
        / "Contents"
        / "PlugIns"
        / "ShortySafariWebExtension.appex"
        / "Contents"
        / "Resources"
        / "manifest.json"
    )
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    manifest.pop("icons")
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

    with pytest.raises(SafariExtensionVerificationError, match="icons mapping"):
        verify_safari_extension(app, require_codesign=False)


def test_release_verify_checks_archive_checksum_and_extension(tmp_path: Path) -> None:
    subprocess.run(["git", "init"], cwd=tmp_path, check=True, capture_output=True)
    (tmp_path / "LICENSE").write_text(
        "GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3\n",
        encoding="utf-8",
    )
    (tmp_path / "NOTICE").write_text(
        ("AGPL-3.0-or-later\nhttps://github.com/peyton/shorty\nWITHOUT ANY WARRANTY\n"),
        encoding="utf-8",
    )
    (tmp_path / "THIRD_PARTY_NOTICES.md").write_text(
        "Shorty has no third-party runtime libraries.\n",
        encoding="utf-8",
    )
    app = make_fake_app(tmp_path)
    add_fake_legal_resources(app)
    add_fake_safari_extension(app)
    source = package_source("1.0.0", tmp_path / "releases", repo_root=tmp_path)
    packaged = package_app(app, "1.0.0", tmp_path / "releases")

    result = verify_release(
        version="1.0.0",
        archive_path=packaged.archive_path,
        checksum_path=packaged.checksum_path,
        source_archive_path=source.archive_path,
        source_checksum_path=source.checksum_path,
    )

    assert result.version == "1.0.0"
    assert result.digest == packaged.digest
    assert result.source_digest == source.digest


def test_legal_resource_validators_require_root_and_bundled_notices(
    tmp_path: Path,
) -> None:
    with pytest.raises(LegalResourceError, match="Missing legal resource"):
        validate_root_legal_resources(tmp_path)

    for filename in ("LICENSE", "NOTICE", "THIRD_PARTY_NOTICES.md"):
        (tmp_path / filename).write_text("incomplete\n", encoding="utf-8")

    with pytest.raises(LegalResourceError, match="required text"):
        validate_root_legal_resources(tmp_path)

    (tmp_path / "LICENSE").write_text(
        "GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3\n",
        encoding="utf-8",
    )
    (tmp_path / "NOTICE").write_text(
        ("AGPL-3.0-or-later\nhttps://github.com/peyton/shorty\nWITHOUT ANY WARRANTY\n"),
        encoding="utf-8",
    )
    (tmp_path / "THIRD_PARTY_NOTICES.md").write_text(
        "Shorty has no third-party runtime libraries.\n",
        encoding="utf-8",
    )

    assert validate_root_legal_resources(tmp_path).files == (
        "LICENSE",
        "NOTICE",
        "THIRD_PARTY_NOTICES.md",
    )

    app = make_fake_app(tmp_path / "bundle")
    add_fake_legal_resources(app)

    assert validate_bundled_legal_resources(app).files == (
        "LICENSE.txt",
        "NOTICE.txt",
        "THIRD_PARTY_NOTICES.md",
    )


def test_source_package_creates_deterministic_archive_and_checksum(
    tmp_path: Path,
) -> None:
    subprocess.run(["git", "init"], cwd=tmp_path, check=True, capture_output=True)
    (tmp_path / "README.md").write_text("# Shorty\n", encoding="utf-8")
    (tmp_path / "NOTICE").write_text("notice\n", encoding="utf-8")
    ignored = tmp_path / ".build" / "ignored.txt"
    ignored.parent.mkdir()
    ignored.write_text("ignore me\n", encoding="utf-8")
    output_dir = tmp_path / ".build" / "releases"

    first = package_source("1.0.0", output_dir=output_dir, repo_root=tmp_path)
    second = package_source("1.0.0", output_dir=output_dir, repo_root=tmp_path)

    assert first.archive_path == output_dir / "shorty-1.0.0-source.tar.gz"
    assert first.checksum_path == output_dir / "shorty-1.0.0-source.tar.gz.sha256"
    assert first.digest == second.digest
    assert (
        first.checksum_path.read_text(encoding="utf-8")
        == f"{first.digest}  shorty-1.0.0-source.tar.gz\n"
    )

    with tarfile.open(first.archive_path, "r:gz") as archive:
        names = archive.getnames()
        assert "shorty-1.0.0/README.md" in names
        assert "shorty-1.0.0/NOTICE" in names
        assert "shorty-1.0.0/.build/ignored.txt" not in names
        assert all(member.uid == 0 for member in archive.getmembers())
        assert all(member.gid == 0 for member in archive.getmembers())
        assert all(member.mtime == 0 for member in archive.getmembers())


def test_appcast_generation_requires_signature_unless_allowed(tmp_path: Path) -> None:
    app = make_fake_app(tmp_path)
    packaged = package_app(app, "1.0.0", tmp_path / "releases")

    with pytest.raises(AppcastGenerateError, match="EdDSA signature"):
        generate_appcast(
            version="1.0.0",
            archive_path=packaged.archive_path,
            download_url="https://example.com/shorty.zip",
            output_path=tmp_path / "appcast.xml",
            ed_signature=None,
        )

    output = generate_appcast(
        version="1.0.0",
        archive_path=packaged.archive_path,
        download_url="https://example.com/shorty.zip",
        output_path=tmp_path / "appcast.xml",
        ed_signature=None,
        allow_unsigned=True,
    )

    assert output.read_text(encoding="utf-8").startswith("<?xml")
    assert "https://github.com/peyton/shorty/releases/tag/v1.0.0" in output.read_text(
        encoding="utf-8"
    )


def test_app_store_candidate_validation_checks_sandbox_and_extension(
    tmp_path: Path,
) -> None:
    app = make_fake_app(tmp_path, version="1.0.0", build_number="123")
    add_fake_safari_extension(
        app,
        bundle_name="ShortyAppStoreSafariWebExtension.appex",
        bundle_id="app.peyton.shorty.appstore.SafariWebExtension",
        version="1.0.0",
        build_number="123",
    )
    info_path = app / "Contents" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "app.peyton.shorty.appstore"
    info_path.write_bytes(plistlib.dumps(info))
    entitlements = tmp_path / "ShortyAppStore.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))

    validate_app_store_candidate(
        app,
        entitlements,
        expected_version="1.0.0",
        expected_build_number="123",
    )


def test_app_store_candidate_validation_rejects_bad_build_number(
    tmp_path: Path,
) -> None:
    app = make_fake_app(tmp_path, version="1.0.0", build_number="preview-test")
    add_fake_safari_extension(
        app,
        bundle_name="ShortyAppStoreSafariWebExtension.appex",
        bundle_id="app.peyton.shorty.appstore.SafariWebExtension",
        version="1.0.0",
        build_number="preview-test",
    )
    info_path = app / "Contents" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "app.peyton.shorty.appstore"
    info_path.write_bytes(plistlib.dumps(info))
    entitlements = tmp_path / "ShortyAppStore.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))

    with pytest.raises(AppStoreValidationError, match="build number"):
        validate_app_store_candidate(
            app,
            entitlements,
            expected_version="1.0.0",
        )


def test_app_store_candidate_validation_requires_app_category(tmp_path: Path) -> None:
    app = make_fake_app(
        tmp_path,
        version="1.0.0",
        build_number="123",
        category="",
    )
    add_fake_safari_extension(
        app,
        bundle_name="ShortyAppStoreSafariWebExtension.appex",
        bundle_id="app.peyton.shorty.appstore.SafariWebExtension",
        version="1.0.0",
        build_number="123",
    )
    info_path = app / "Contents" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "app.peyton.shorty.appstore"
    info_path.write_bytes(plistlib.dumps(info))
    entitlements = tmp_path / "ShortyAppStore.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))

    with pytest.raises(AppStoreValidationError, match="Expected app-store category"):
        validate_app_store_candidate(
            app,
            entitlements,
            expected_version="1.0.0",
            expected_build_number="123",
        )


def test_app_store_candidate_validation_requires_export_compliance_key(
    tmp_path: Path,
) -> None:
    app = make_fake_app(
        tmp_path,
        version="1.0.0",
        build_number="123",
    )
    add_fake_safari_extension(
        app,
        bundle_name="ShortyAppStoreSafariWebExtension.appex",
        bundle_id="app.peyton.shorty.appstore.SafariWebExtension",
        version="1.0.0",
        build_number="123",
    )
    info_path = app / "Contents" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "app.peyton.shorty.appstore"
    del info["ITSAppUsesNonExemptEncryption"]
    info_path.write_bytes(plistlib.dumps(info))
    entitlements = tmp_path / "ShortyAppStore.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))

    with pytest.raises(
        AppStoreValidationError,
        match="ITSAppUsesNonExemptEncryption",
    ):
        validate_app_store_candidate(
            app,
            entitlements,
            expected_version="1.0.0",
            expected_build_number="123",
        )


# ---------------------------------------------------------------------------
# Doctor checks
# ---------------------------------------------------------------------------


def test_doctor_codesign_identity_checks() -> None:
    assert check_codesign_identity({}).status == Status.FAIL
    result = check_codesign_identity({"SHORTY_CODESIGN_IDENTITY": ""})
    assert result.status == Status.FAIL

    result = check_codesign_identity({"SHORTY_CODESIGN_IDENTITY": "-"})
    assert result.status == Status.WARN

    result = check_codesign_identity(
        {"SHORTY_CODESIGN_IDENTITY": "Developer ID Application: Test (ABC123)"}
    )
    assert result.status == Status.PASS


def test_doctor_team_id_checks() -> None:
    assert check_team_id({}).status == Status.FAIL
    assert check_team_id({"TEAM_ID": ""}).status == Status.FAIL
    assert check_team_id({"TEAM_ID": "3VDQ4656LX"}).status == Status.PASS


def test_doctor_version_file_checks(tmp_path: Path) -> None:
    assert check_version_file(tmp_path).status == Status.FAIL

    (tmp_path / "VERSION").write_text("invalid\n", encoding="utf-8")
    assert check_version_file(tmp_path).status == Status.FAIL

    (tmp_path / "VERSION").write_text("1.0.0\n", encoding="utf-8")
    result = check_version_file(tmp_path)
    assert result.status == Status.PASS
    assert result.message == "1.0.0"


def test_doctor_entitlement_file_checks(tmp_path: Path) -> None:
    ent_dir = tmp_path / "app" / "Shorty"
    ent_dir.mkdir(parents=True)

    result = check_entitlement_file(
        "Shorty.entitlements",
        "Developer ID signing",
        entitlements_dir=ent_dir,
        repo_root=tmp_path,
    )
    assert result.status == Status.FAIL

    ent_path = ent_dir / "Shorty.entitlements"
    ent_path.write_bytes(
        plistlib.dumps(
            {"com.apple.security.application-groups": ["group.app.peyton.shorty"]}
        )
    )
    result = check_entitlement_file(
        "Shorty.entitlements",
        "Developer ID signing",
        entitlements_dir=ent_dir,
        repo_root=tmp_path,
    )
    assert result.status == Status.PASS


def test_doctor_app_store_entitlements_require_sandbox(tmp_path: Path) -> None:
    ent_dir = tmp_path / "app" / "Shorty"
    ent_dir.mkdir(parents=True)

    ent_path = ent_dir / "ShortyAppStore.entitlements"
    ent_path.write_bytes(
        plistlib.dumps(
            {"com.apple.security.application-groups": ["group.app.peyton.shorty"]}
        )
    )
    result = check_entitlement_file(
        "ShortyAppStore.entitlements",
        "App Store / TestFlight builds",
        entitlements_dir=ent_dir,
        repo_root=tmp_path,
    )
    assert result.status == Status.FAIL
    assert "Sandbox" in result.message

    ent_path.write_bytes(
        plistlib.dumps(
            {
                "com.apple.security.app-sandbox": True,
                "com.apple.security.application-groups": ["group.app.peyton.shorty"],
            }
        )
    )
    result = check_entitlement_file(
        "ShortyAppStore.entitlements",
        "App Store / TestFlight builds",
        entitlements_dir=ent_dir,
        repo_root=tmp_path,
    )
    assert result.status == Status.PASS


def test_doctor_notarization_credentials_checks(tmp_path: Path) -> None:
    assert check_notarization_credentials({}).status == Status.FAIL

    result = check_notarization_credentials({"NOTARYTOOL_PROFILE": "my-profile"})
    assert result.status == Status.PASS

    result = check_notarization_credentials(
        {
            "SHORTY_APP_STORE_CONNECT_KEY_ID": "ABC123",
            "SHORTY_APP_STORE_CONNECT_ISSUER_ID": "uuid-here",
        }
    )
    assert result.status == Status.FAIL
    assert "SHORTY_APP_STORE_CONNECT_KEY_PATH" in result.message

    key_file = tmp_path / "AuthKey_ABC123.p8"
    key_file.write_text("fake-key", encoding="utf-8")
    result = check_notarization_credentials(
        {
            "SHORTY_APP_STORE_CONNECT_KEY_PATH": str(key_file),
            "SHORTY_APP_STORE_CONNECT_KEY_ID": "ABC123",
            "SHORTY_APP_STORE_CONNECT_ISSUER_ID": "uuid-here",
        }
    )
    assert result.status == Status.PASS

    result = check_notarization_credentials(
        {
            "SHORTY_APP_STORE_CONNECT_KEY_PATH": "/nonexistent/key.p8",
            "SHORTY_APP_STORE_CONNECT_KEY_ID": "ABC123",
            "SHORTY_APP_STORE_CONNECT_ISSUER_ID": "uuid-here",
        }
    )
    assert result.status == Status.FAIL
    assert "not found" in result.message


def test_doctor_testflight_credentials_checks() -> None:
    assert check_testflight_credentials({}).status == Status.FAIL

    result = check_testflight_credentials(
        {
            "SHORTY_APP_STORE_CONNECT_KEY_PATH": "/some/key.p8",
            "SHORTY_APP_STORE_CONNECT_KEY_ID": "ABC123",
            "SHORTY_APP_STORE_CONNECT_ISSUER_ID": "uuid-here",
        }
    )
    assert result.status == Status.WARN
    assert "profile pair is missing" in result.message

    result = check_testflight_credentials(
        {
            "SHORTY_APP_STORE_CONNECT_KEY_PATH": "/some/key.p8",
            "SHORTY_APP_STORE_CONNECT_KEY_ID": "ABC123",
            "SHORTY_APP_STORE_CONNECT_ISSUER_ID": "uuid-here",
            "SHORTY_APP_STORE_APP_PROFILE": "base64-app-profile",
            "SHORTY_APP_STORE_EXTENSION_PROFILE": "base64-extension-profile",
            "SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING": "1",
        }
    )
    assert result.status == Status.PASS
    assert "local App Store signing enabled" in result.message

    result = check_testflight_credentials({"SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING": "1"})
    assert result.status == Status.WARN


def test_doctor_run_produces_complete_report(tmp_path: Path) -> None:
    (tmp_path / "VERSION").write_text("1.0.0\n", encoding="utf-8")
    ent_dir = tmp_path / "app" / "Shorty"
    ent_dir.mkdir(parents=True)
    for name in (
        "Shorty.entitlements",
        "ShortySafariWebExtension.entitlements",
    ):
        (ent_dir / name).write_bytes(
            plistlib.dumps(
                {"com.apple.security.application-groups": ["group.app.peyton.shorty"]}
            )
        )
    (ent_dir / "ShortyAppStore.entitlements").write_bytes(
        plistlib.dumps(
            {
                "com.apple.security.app-sandbox": True,
                "com.apple.security.application-groups": ["group.app.peyton.shorty"],
            }
        )
    )

    env = {"TEAM_ID": "3VDQ4656LX", "NOTARYTOOL_PROFILE": "test-profile"}
    report = run_doctor(env=env, repo_root=tmp_path)

    section_titles = [title for title, _ in report.sections]
    assert "General" in section_titles
    assert "Entitlements" in section_titles
    assert "Developer ID Signing" in section_titles
    assert "Notarization" in section_titles
    assert "TestFlight / App Store" in section_titles


def test_doctor_format_report_includes_all_sections() -> None:
    report = DoctorReport()
    report.begin_section("Test Section")
    report.add(CheckResult("test-check", Status.PASS, "OK"))
    report.begin_section("Another Section")
    report.add(CheckResult("fail-check", Status.FAIL, "Bad", "Fix it"))

    output = format_report(report)
    assert "Test Section" in output
    assert "Another Section" in output
    assert "test-check" in output
    assert "fail-check" in output
    assert "Fix it" in output
    assert "1 failed" in output
    assert "1 passed" in output
