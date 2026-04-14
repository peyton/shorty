from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from scripts.tooling.package_app import REPO_ROOT

SOURCE_URL = "https://github.com/peyton/shorty"
LICENSE_ID = "AGPL-3.0-or-later"

ROOT_LEGAL_FILES = (
    "LICENSE",
    "NOTICE",
    "THIRD_PARTY_NOTICES.md",
)

BUNDLED_LEGAL_FILES = (
    "LICENSE.txt",
    "NOTICE.txt",
    "THIRD_PARTY_NOTICES.md",
)

ROOT_REQUIRED_MARKERS = {
    "LICENSE": ("GNU AFFERO GENERAL PUBLIC LICENSE", "Version 3"),
    "NOTICE": (LICENSE_ID, SOURCE_URL, "WITHOUT ANY WARRANTY"),
    "THIRD_PARTY_NOTICES.md": ("no third-party runtime libraries",),
}

BUNDLED_REQUIRED_MARKERS = {
    "LICENSE.txt": ("GNU AFFERO GENERAL PUBLIC LICENSE", "Version 3"),
    "NOTICE.txt": (LICENSE_ID, SOURCE_URL, "WITHOUT ANY WARRANTY"),
    "THIRD_PARTY_NOTICES.md": ("no third-party runtime libraries",),
}


class LegalResourceError(RuntimeError):
    """Raised when required open source legal resources are missing."""


@dataclass(frozen=True)
class LegalResourceResult:
    path: Path
    files: tuple[str, ...]


def validate_text_file(
    path: Path,
    markers: tuple[str, ...],
) -> None:
    if not path.is_file():
        raise LegalResourceError(f"Missing legal resource: {path}")

    text = path.read_text(encoding="utf-8")
    lowered = text.lower()
    for marker in markers:
        if marker.lower() not in lowered:
            raise LegalResourceError(
                f"Legal resource {path} is missing required text {marker!r}."
            )


def validate_root_legal_resources(
    repo_root: Path = REPO_ROOT,
) -> LegalResourceResult:
    for filename in ROOT_LEGAL_FILES:
        validate_text_file(repo_root / filename, ROOT_REQUIRED_MARKERS[filename])
    return LegalResourceResult(path=repo_root, files=ROOT_LEGAL_FILES)


def bundled_legal_root(app_path: Path) -> Path:
    resources_root = app_path / "Contents" / "Resources"
    nested_legal_root = resources_root / "Legal"
    if nested_legal_root.is_dir():
        return nested_legal_root
    return resources_root


def validate_bundled_legal_resources(app_path: Path) -> LegalResourceResult:
    legal_root = bundled_legal_root(app_path)
    for filename in BUNDLED_LEGAL_FILES:
        validate_text_file(legal_root / filename, BUNDLED_REQUIRED_MARKERS[filename])
    return LegalResourceResult(path=legal_root, files=BUNDLED_LEGAL_FILES)
