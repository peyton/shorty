# SemVer preview releases with TestFlight-compatible builds

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds. The plan follows the repository instruction that complex release changes use the ExecPlan format described in `~/.agents/PLANS.md`.

## Purpose / Big Picture

Shorty needs one clear public app version and separate preview identifiers. After this work, maintainers can publish GitHub preview releases from every successful `master` CI run without pretending that each preview is a new public SemVer release. The sandboxed App Store build remains compatible with TestFlight because its user-facing version is always the root SemVer value and each upload uses a separate positive numeric Apple build number.

The behavior is visible by running `just app-package VERSION=1.0.0 ARTIFACT_LABEL=preview-test` and observing an archive named `shorty-preview-test-macos.zip` whose app bundle still reports `CFBundleShortVersionString` as `1.0.0`. It is also visible by running `just app-store-build VERSION=1.0.0 BUILD_NUMBER=123` and `just app-store-validate VERSION=1.0.0 BUILD_NUMBER=123`.

## Progress

- [x] (2026-04-14 00:00Z) Inspected the existing release scripts, Tuist project settings, CI workflow, and App Store candidate lane.
- [x] (2026-04-14 00:00Z) Added root `VERSION` and shared Python validation helpers for app SemVer, Apple build numbers, preview labels, and artifact labels.
- [x] (2026-04-14 00:00Z) Updated packaging and App Store shell scripts so bundle version and artifact labels are separate.
- [x] (2026-04-14 00:00Z) Added GitHub preview release workflow and release documentation.
- [x] (2026-04-14 00:00Z) Added Python tests and refreshed `uv.lock` to project version `1.0.0`.
- [x] (2026-04-14 00:00Z) Ran lint, Python tests, preview packaging, App Store build, App Store validation, and credential-gate verification.

## Surprises & Discoveries

- Observation: The existing App Store lane only built and validated `ShortyAppStore.app`; it did not create an `.xcarchive` or upload to App Store Connect.
  Evidence: `scripts/tooling/app_store_build.sh` ran `xcodebuild ... build`, and `scripts/tooling/app_store_validate.py` only inspected the built app bundle.
- Observation: `Project.swift` already hardcoded app version `1.0.0`, but Python project metadata and `uv.lock` still declared `0.1.0`.
  Evidence: `app/Shorty/Project.swift` contained `let marketingVersion = "1.0.0"` and `pyproject.toml` contained `version = "0.1.0"` before this work.
- Observation: Tuist did not pick up arbitrary `SHORTY_BUILD_NUMBER` through `ProcessInfo.processInfo.environment` in the manifest, so preview packaging initially built an archive with `CFBundleVersion=1`.
  Evidence: Inspecting `.build/releases/shorty-preview-test-macos.zip` after the first packaging run printed `1.0.0` and `1`; after bridging through `TUIST_SHORTY_BUILD_NUMBER`, the same check printed `1.0.0` and `123`.

## Decision Log

- Decision: Treat the root `VERSION` file as the canonical SemVer source and use `SHORTY_MARKETING_VERSION` only as a build-time override.
  Rationale: Public releases should require a checked-in version bump, while CI and local packaging can still inject the value explicitly.
  Date/Author: 2026-04-14 / Codex.
- Decision: Use `preview-<12-character-sha>` for GitHub preview tags and assets, but never in `CFBundleShortVersionString`.
  Rationale: TestFlight and App Store builds need a normal app version; preview identity belongs in GitHub release metadata and filenames.
  Date/Author: 2026-04-14 / Codex.
- Decision: Keep TestFlight upload manual and credential-gated.
  Rationale: App Store Connect uploads require Apple signing and API credentials, and the user explicitly chose compatibility without automatic uploads for every `master` change.
  Date/Author: 2026-04-14 / Codex.
- Decision: Bridge `SHORTY_MARKETING_VERSION` and `SHORTY_BUILD_NUMBER` into Tuist-specific `TUIST_SHORTY_MARKETING_VERSION` and `TUIST_SHORTY_BUILD_NUMBER` inside repo tooling.
  Rationale: The user-facing command surface should use the `SHORTY_*` variables from the plan, while Tuist manifests reliably consume the `TUIST_*` environment.
  Date/Author: 2026-04-14 / Codex.

## Outcomes & Retrospective

Implementation is complete. The repo now has a root SemVer source, preview GitHub release automation, package artifact labels that do not alter app bundle SemVer, and TestFlight-compatible App Store build/archive/export commands. The archive/export path remains intentionally gated on signing or App Store Connect credentials.

## Context and Orientation

The repo root is `/Users/peyton/.codex/worktrees/6ab4/shorty`. `app/Shorty/Project.swift` is the Tuist project manifest that writes Xcode build settings such as `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` into every app and extension target. `scripts/tooling/package_app.py` writes direct-download zip archives. `scripts/tooling/app_store_build.sh` and `scripts/tooling/app_store_validate.py` handle the sandboxed `ShortyAppStore` target. GitHub Actions workflows live under `.github/workflows`.

SemVer means the public app version in the form `MAJOR.MINOR.PATCH`, such as `1.0.0`. An Apple build number means the value in `CFBundleVersion`; for this work it must be a positive numeric string such as `123`. A preview label means a GitHub-only identifier such as `preview-abcdef012345`; it is not an app version.

## Plan of Work

Create `VERSION` at the repo root and make all release scripts validate app versions against strict `MAJOR.MINOR.PATCH`. Update the Tuist manifest so the app and both Safari extension targets receive `MARKETING_VERSION` from `SHORTY_MARKETING_VERSION` or the root file, and `CURRENT_PROJECT_VERSION` from `SHORTY_BUILD_NUMBER` or `1`.

Update packaging so it receives a SemVer `VERSION` and an optional `ARTIFACT_LABEL`. The app bundle must match `VERSION`; only the zip filename and checksum filename use `ARTIFACT_LABEL`.

Add App Store archive and TestFlight export scripts. The archive command must require either explicit local signing approval or App Store Connect API credentials. The TestFlight upload command must require App Store Connect API credentials and use `xcodebuild -exportArchive` with `method=app-store-connect`, `destination=upload`, `manageAppVersionAndBuildNumber=false`, and `testFlightInternalTestingOnly=true`.

Add `.github/workflows/preview-release.yml` triggered by successful CI workflow runs on `master`. It checks out the exact tested commit, builds an ad-hoc-signed direct-download package with a preview artifact label, deletes any previous preview release for the same commit, and creates a prerelease that is not marked latest.

## Concrete Steps

From `/Users/peyton/.codex/worktrees/6ab4/shorty`, edit the files named above. Then run:

    uv lock
    chmod +x scripts/tooling/app_store_archive.sh scripts/tooling/app_store_export_testflight.sh
    mise exec -- just ci-python
    mise exec -- just ci-lint
    SHORTY_BUILD_NUMBER=123 mise exec -- just app-package VERSION=1.0.0 ARTIFACT_LABEL=preview-test
    mise exec -- just app-store-build VERSION=1.0.0 BUILD_NUMBER=123
    mise exec -- just app-store-validate VERSION=1.0.0 BUILD_NUMBER=123

## Validation and Acceptance

Python tests must cover SemVer validation, Apple build-number validation, preview label creation, packaging with a separate artifact label, and App Store candidate version checks. `just ci-python` and `just ci-lint` must exit 0. On macOS, preview packaging must create `.build/releases/shorty-preview-test-macos.zip`, and the extracted `Info.plist` must still contain `CFBundleShortVersionString=1.0.0` and `CFBundleVersion=123`. The App Store validation command must pass for version `1.0.0` and build number `123`.

## Idempotence and Recovery

All generated artifacts go under `.build`, `.DerivedData`, or `uv.lock`. Re-running the preview workflow for the same commit deletes and recreates only the `preview-<sha>` release and tag. If App Store signing credentials are absent, archive/export scripts fail before creating a public-looking upload.

## Artifacts and Notes

Important expected outputs:

    Created .build/releases/shorty-preview-test-macos.zip
    Created .build/releases/shorty-preview-test-macos.zip.sha256
    App Store candidate verified: .../ShortyAppStore.app
    App Store archive requires explicit signing credentials.

## Interfaces and Dependencies

The new Python module `scripts.tooling.versioning` exposes `validate_app_version`, `validate_apple_build_number`, `preview_label_for_sha`, and `validate_artifact_label`. The `just` interface exposes `app-package VERSION=... ARTIFACT_LABEL=...`, `app-store-build VERSION=... BUILD_NUMBER=...`, `app-store-validate VERSION=... BUILD_NUMBER=...`, `app-store-archive VERSION=... BUILD_NUMBER=...`, and `app-store-export-testflight VERSION=... BUILD_NUMBER=...`.
