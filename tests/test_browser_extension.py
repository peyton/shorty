from __future__ import annotations

import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CORE_ROOT = REPO_ROOT / "app" / "Shorty" / "Sources" / "ShortyCore"
EXTENSION_ROOT = CORE_ROOT / "Resources" / "BrowserExtension"
SAFARI_EXTENSION_ROOT = (
    REPO_ROOT / "app" / "Shorty" / "Sources" / "ShortySafariWebExtension" / "Resources"
)


def _swift_domains(name: str) -> set[str]:
    source = (CORE_ROOT / "DomainNormalizer.swift").read_text(encoding="utf-8")
    pattern = rf"private static let {name}: Set<String> = \[(.*?)\]"
    match = re.search(pattern, source, re.DOTALL)
    assert match is not None
    return set(re.findall(r'"([^"]+)"', match.group(1)))


def _background_domains(root: Path, constant: str) -> set[str]:
    source = (root / "background.js").read_text(encoding="utf-8")
    pattern = rf"const {constant} = (?:new Set\()?\[(.*?)\](?:\))?;"
    match = re.search(pattern, source, re.DOTALL)
    assert match is not None
    return set(re.findall(r'"([^"]+)"', match.group(1)))


def _manifest_matches(root: Path) -> set[str]:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    matches = set(manifest["content_scripts"][0]["matches"])
    matches.update(manifest.get("host_permissions", []))
    return matches


def test_browser_extension_declares_required_permissions() -> None:
    manifest = json.loads((EXTENSION_ROOT / "manifest.json").read_text())

    assert manifest["manifest_version"] == 3
    assert manifest["homepage_url"] == "https://github.com/peyton/shorty"
    assert set(manifest["permissions"]) >= {"nativeMessaging", "tabs"}
    assert manifest["background"]["service_worker"] == "background.js"
    matches = manifest["content_scripts"][0]["matches"]
    assert "<all_urls>" not in matches
    assert "*://docs.google.com/*" in matches
    assert "*://*.slack.com/*" in matches


def test_background_worker_clears_domain_for_unsupported_pages() -> None:
    background = (EXTENSION_ROOT / "background.js").read_text(encoding="utf-8")

    assert 'type: "domain_cleared"' in background
    assert "let lastSentDomain = undefined;" in background
    assert "lastSentDomain = undefined;" in background
    assert "lastSentDomain = null;" in background
    assert "sendClearDomain();" in background
    assert "sendActiveTabDomain();" in background
    assert "protocol_version: PROTOCOL_VERSION" in background
    sync_comment = "Keep this list in sync with DomainNormalizer.supportedWebAppDomains"
    assert sync_comment in background


def test_browser_domain_lists_match_domain_normalizer() -> None:
    exact_domains = _swift_domains("exactDomainMatches")
    root_domains = _swift_domains("rootDomainMatches")
    supported_domains = exact_domains | root_domains

    for root in [EXTENSION_ROOT, SAFARI_EXTENSION_ROOT]:
        assert _background_domains(root, "SUPPORTED_DOMAINS") == supported_domains
        assert _background_domains(root, "EXACT_DOMAINS") == exact_domains

        matches = _manifest_matches(root)
        for domain in exact_domains:
            assert f"*://{domain}/*" in matches
            assert f"*://*.{domain}/*" not in matches

        for domain in root_domains:
            assert f"*://{domain}/*" in matches
            assert f"*://*.{domain}/*" in matches
