from __future__ import annotations

import json
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
EXTENSION_ROOT = (
    REPO_ROOT
    / "app"
    / "Shorty"
    / "Sources"
    / "ShortyCore"
    / "Resources"
    / "BrowserExtension"
)


def test_browser_extension_declares_required_permissions() -> None:
    manifest = json.loads((EXTENSION_ROOT / "manifest.json").read_text())

    assert manifest["manifest_version"] == 3
    assert set(manifest["permissions"]) >= {"nativeMessaging", "tabs"}
    assert manifest["background"]["service_worker"] == "background.js"
    assert manifest["content_scripts"][0]["matches"] == ["<all_urls>"]


def test_background_worker_clears_domain_for_unsupported_pages() -> None:
    background = (EXTENSION_ROOT / "background.js").read_text(encoding="utf-8")

    assert 'type: "domain_cleared"' in background
    assert "let lastSentDomain = undefined;" in background
    assert "lastSentDomain = undefined;" in background
    assert "lastSentDomain = null;" in background
    assert "sendClearDomain();" in background
    assert "sendActiveTabDomain();" in background
