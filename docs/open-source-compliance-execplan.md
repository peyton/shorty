# Open Source and AGPL Readiness

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository follows the ExecPlan guidance in `~/.agents/PLANS.md`.

## Purpose / Big Picture

After this work, Shorty can be published as an AGPL-3.0-or-later open source macOS app with clear license files, in-app attribution, source availability in release artifacts, and tests that prevent legal-resource drift. A user can open Settings > About to see the license and source location, download the app and matching source archive, and verify both with checksums.

## Progress

- [x] (2026-04-14T09:56:55Z) Inspected the repo and confirmed there was no root license, no bundled legal resources, no runtime Swift dependency, and an existing Settings > About surface.
- [x] (2026-04-14T09:56:55Z) Chose AGPL-3.0-or-later and direct-download as the primary public release lane.
- [x] (2026-04-14T10:18:51Z) Added root and bundled legal files.
- [x] (2026-04-14T10:18:51Z) Wired source archive generation into release tooling.
- [x] (2026-04-14T10:18:51Z) Added in-app open source and attribution UI.
- [x] (2026-04-14T10:18:51Z) Updated website and repository documentation.
- [x] (2026-04-14T10:18:51Z) Added tests and ran verification.

## Surprises & Discoveries

- Observation: `ShortyScreenshots` already referenced `UpdateStatus.currentVersion`, but `UpdateStatus` did not define it.
  Evidence: searching `currentVersion` found a fixture initializer argument in `app/Shorty/Sources/ShortyScreenshots/main.swift` and no matching property in `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`.

- Observation: Tuist flattens the app legal resource directory into `Shorty.app/Contents/Resources` for the current app target.
  Evidence: the built release app contained `LICENSE.txt`, `NOTICE.txt`, and `THIRD_PARTY_NOTICES.md` directly under `Contents/Resources`, so the release verifier accepts either `Contents/Resources/Legal` or the flattened resources root.

- Observation: The legal-resource validators need exact human-readable audit phrases.
  Evidence: `release-verify` initially failed until `NOTICE` contained `WITHOUT ANY WARRANTY` contiguously and third-party notices contained `no third-party runtime libraries`.

## Decision Log

- Decision: License Shorty as `AGPL-3.0-or-later`.
  Rationale: The project is intended to remain free for all users while allowing future AGPL versions.
  Date/Author: 2026-04-14 / Codex

- Decision: Keep the App Store target but document it as legal-review gated.
  Rationale: Direct download can carry app and source archives directly; App Store publication needs separate legal review for source availability and store terms.
  Date/Author: 2026-04-14 / Codex

## Outcomes & Retrospective

Implemented. Shorty now declares AGPL-3.0-or-later at the repo root, bundles legal resources in the app, surfaces license/source/support/security/attribution in Settings, publishes source archive tooling, links source releases in appcasts and the website, and validates legal resources in release preflight and release verification.

Verification completed on 2026-04-14:

    just test-python
    just web-check
    just generate
    just test-app
    just build
    just lint
    just marketing-screenshots
    just source-package VERSION=1.0.0
    SHORTY_ALLOW_AD_HOC_RELEASE=1 SHORTY_CODESIGN_IDENTITY=- just app-package VERSION=1.0.0
    just release-verify VERSION=1.0.0

Final release artifacts verified:

    .build/releases/shorty-1.0.0-macos.zip
    .build/releases/shorty-1.0.0-macos.zip.sha256
    .build/releases/shorty-1.0.0-source.tar.gz
    .build/releases/shorty-1.0.0-source.tar.gz.sha256

The source checksum is intentionally not copied into this tracked source file,
because doing so would change the source archive contents after every archive
generation. The generated `.sha256` artifact is the source of truth.

## Context and Orientation

Shorty is a Tuist-based Swift macOS menu-bar app under `app/Shorty`, with release and validation tooling under `scripts/tooling`, a static website under `web`, and Python tests under `tests`. The app already has a Settings window in `app/Shorty/Sources/Shorty/SettingsView.swift`, release status models in `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`, and direct-download packaging scripts that produce macOS zip archives and checksums under `.build/releases`.

The work adds legal files at the repo root, copies app-visible legal resources under `app/Shorty/Sources/Shorty/Resources/Legal`, adds source archive packaging, and updates release checks so legal resources are not accidentally omitted.

## Plan of Work

First, add root legal and contributor documents: `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, and `docs/open-source.md`. Copy the license, notice, and third-party notices into the app's `Resources/Legal` directory so they ship in `Shorty.app`.

Second, add deterministic source archive tooling in `scripts/tooling/source_package.py` and a shell wrapper, expose it through `just source-package`, and include it in direct-download release lanes before app verification.

Third, extend `UpdateStatus` with the current version and source URL. Update Settings > Updates and Settings > About to surface license, source, support, security, and attribution information.

Fourth, update the static website and docs to link to the license page and source archives. Update validators and tests so the license page is required.

Finally, run Python, web, Swift, build, screenshot, source packaging, app packaging, and release verification commands.

## Concrete Steps

Work from the repository root:

    /Users/peyton/.codex/worktrees/8b22/shorty

Use `apply_patch` for manual edits, then run:

    just test-python
    just web-check
    just generate
    just test-app
    just build
    just marketing-screenshots
    just source-package VERSION=1.0.0
    SHORTY_ALLOW_AD_HOC_RELEASE=1 SHORTY_CODESIGN_IDENTITY=- just app-package VERSION=1.0.0
    just release-verify VERSION=1.0.0

## Validation and Acceptance

Acceptance requires all verification commands to pass. In the app, Settings > About must display AGPL-3.0-or-later, the source URL, no-warranty language, and runtime attribution. Settings > Updates must display the current version and source link. Release archives must include both the app archive and source archive checksums.

## Idempotence and Recovery

The source package command must be deterministic and safe to rerun for the same version. Release verification must fail clearly if legal files or bundled legal resources are missing. Generated build outputs remain under ignored `.build` and `.DerivedData` directories.

## Artifacts and Notes

The most important artifacts are root legal files, bundled legal resources, source archive/checksum outputs, updated Settings UI, and passing tests.

## Interfaces and Dependencies

`UpdateStatus` in `app/Shorty/Sources/ShortyCore/ReleaseModels.swift` must expose:

    public let currentVersion: String
    public let sourceURL: URL?

The initializer must provide defaults so existing call sites remain source-compatible.
