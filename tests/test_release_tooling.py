from __future__ import annotations

import plistlib
import subprocess
import tarfile
import zipfile
from pathlib import Path

import pytest

from scripts.tooling.app_store_validate import validate_app_store_candidate
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
from scripts.tooling.safari_extension_verify import verify_safari_extension
from scripts.tooling.source_package import package_source


def make_fake_app(root: Path, version: str = "1.0.0") -> Path:
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
                "CFBundleVersion": "1",
            }
        )
    )
    return app


def add_fake_safari_extension(
    app: Path,
    bundle_name: str = "ShortySafariWebExtension.appex",
    bundle_id: str = "app.peyton.shorty.SafariWebExtension",
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
                "CFBundleShortVersionString": "1.0.0",
                "CFBundleVersion": "1",
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
            '"background":{"service_worker":"background.js"}}\n'
        ),
        encoding="utf-8",
    )
    return extension


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
    app = make_fake_app(tmp_path)
    add_fake_safari_extension(
        app,
        bundle_name="ShortyAppStoreSafariWebExtension.appex",
        bundle_id="app.peyton.shorty.appstore.SafariWebExtension",
    )
    info_path = app / "Contents" / "Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    info["CFBundleIdentifier"] = "app.peyton.shorty.appstore"
    info_path.write_bytes(plistlib.dumps(info))
    entitlements = tmp_path / "ShortyAppStore.entitlements"
    entitlements.write_bytes(plistlib.dumps({"com.apple.security.app-sandbox": True}))

    validate_app_store_candidate(app, entitlements)
