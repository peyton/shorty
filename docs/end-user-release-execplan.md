# End-user release hardening with Safari extension

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

The repository instructions refer to `~/.agent/PLANS.md`, but that file is not present in this environment. The available guide is `/Users/peyton/.agents/PLANS.md`; this document follows that guide and is self-contained so a novice can continue the work from only this file and the current working tree.

## Purpose / Big Picture

Shorty is a macOS menu-bar app that translates a small set of user-facing shortcut intents into app-specific keyboard shortcuts and actions. The goal of this release pass is to make Shorty credible for daily end users: it must install cleanly, explain required macOS permissions, support Safari through a signed extension path, keep Chrome-family browser setup understandable, expose enough diagnostics for support, and provide a secondary App Store candidate lane without weakening the direct-download product.

At the end of this plan, a maintainer can run the root `just` commands to build, test, package, verify, and inspect the release artifacts. A user can launch the app, follow first-run setup, grant Accessibility, see whether Safari and browser bridges are available, understand what the active app supports, and export a support bundle without using Terminal.

## Progress

- [x] 2026-04-14 Read `/Users/peyton/.agents/PLANS.md` and created this ExecPlan.
- [x] 2026-04-14 Confirmed the baseline app is a Tuist macOS project under `app/Shorty`, with release scripts under `scripts/tooling` and tests under `tests` and `app/Shorty/Tests`.
- [x] 2026-04-14 Fixed the known markdown lint blocker in `docs/marketing-screenshots-execplan.md`.
- [x] 2026-04-14 Added release-facing ShortyCore types for shortcut profiles, diagnostics, browser sources, Safari extension status, update state, and release verification.
- [x] 2026-04-14 Wired app state and SwiftUI surfaces for setup, updates, Safari status, Chrome bridge status, shortcut review scaffolding, diagnostics, and support export.
- [x] 2026-04-14 Added Tuist targets/resources for a signed Safari Web Extension path and a sandboxed App Store candidate target.
- [x] 2026-04-14 Added release commands for DMG packaging, release verification, appcast generation, Safari extension verification, App Store candidate build/validation, and energy profiling helpers.
- [x] 2026-04-14 Added unit and integration tests for the new model, release tooling, browser context routing, and diagnostics.
- [x] 2026-04-14 Ran final verification: `just ci`, `just app-package VERSION=1.0.0`, `just dmg-package VERSION=1.0.0`, `just release-verify VERSION=1.0.0`, `just safari-extension-verify`, `just app-store-build`, and `just app-store-validate`.

## Surprises & Discoveries

- Observation: The current worktree is detached at `HEAD`.
  Evidence: `git status --porcelain=v1 -b` printed `## HEAD (no branch)`.
- Observation: The Xcode command line reports `Xcode 26.5` without the word `Beta`, but previous build paths show `/Applications/Xcode-26.5.0-Beta.app`.
  Evidence: `xcodebuild -version` printed `Xcode 26.5`; previous build logs used `/Applications/Xcode-26.5.0-Beta.app`.
- Observation: The existing full CI was blocked by Markdown indentation, not Swift or Python tests.
  Evidence: `just ci` failed in `rumdl check --diff` for `docs/marketing-screenshots-execplan.md`; `just test-python`, `just web-check`, `just test-app`, and `just integration` passed individually.
- Observation: The Safari Web Extension can be bundled by Tuist as an app extension target and verified structurally in local builds.
  Evidence: `just build` produced `Shorty.app/Contents/PlugIns/ShortySafariWebExtension.appex`, and `just safari-extension-verify` confirmed the appex, bundle identifier, native handler, and manifest.
- Observation: Appcast generation must be signature-gated for real direct-download updates.
  Evidence: `scripts/tooling/appcast_generate.py` refuses release appcasts unless `SHORTY_SPARKLE_ED_SIGNATURE` is provided or an explicit development-only unsigned flag is passed.
- Observation: The App Store candidate needs a distinct Safari extension target because Xcode validates embedded extension bundle identifiers against the containing app identifier.
  Evidence: The first App Store candidate build failed in `ValidateEmbeddedBinary` when it embedded `app.peyton.shorty.SafariWebExtension`; the build passed after adding `ShortyAppStoreSafariWebExtension` with bundle id `app.peyton.shorty.appstore.SafariWebExtension`.

## Decision Log

- Decision: Keep Developer ID direct download as the primary product lane.
  Rationale: The full shortcut remapping product depends on global keyboard event handling and Accessibility behavior that is more appropriate for direct distribution than Mac App Store review.
  Date/Author: 2026-04-14 / Codex
- Decision: Add a signed Safari Web Extension path to the primary direct-download app.
  Rationale: The user has an Apple Developer account and explicitly asked for Safari support; a bundled Safari extension gives Safari web adapters a native Apple distribution path without relying on Chrome native messaging.
  Date/Author: 2026-04-14 / Codex
- Decision: Treat App Store distribution as a secondary candidate target.
  Rationale: Mac App Store sandboxing and review constraints may prevent the full global event tap product from shipping unchanged; a separate target lets the app expose setup, Safari extension, diagnostics, and review-safe behavior without compromising the Developer ID product.
  Date/Author: 2026-04-14 / Codex
- Decision: Use Sparkle only in direct-download lanes.
  Rationale: Sparkle is a standard direct-download updater and is not needed for App Store builds, where updates are managed by the store.
  Date/Author: 2026-04-14 / Codex

## Outcomes & Retrospective

This plan reached the implementation checkpoint for the requested release backlog. The implementation now has ShortyCore release models, Safari extension target/resources, a separate App Store candidate app and Safari extension target, first-run and release-facing settings surfaces, support bundle export, stable Chrome bridge helper installation, DMG/appcast/release verification tooling, energy profiling helpers, documentation, and tests. Local CI and packaging verification pass; notarization, Gatekeeper approval, stapling, Sparkle signing, and App Store upload remain credential-gated public release operations.

## Context and Orientation

Work from repository root `/Users/peyton/.codex/worktrees/034e/shorty`.

The main app target is `Shorty`, defined in `app/Shorty/Project.swift`. It is a menu-bar app with SwiftUI views in `app/Shorty/Sources/Shorty`. The app logic lives in `ShortyCore`, under `app/Shorty/Sources/ShortyCore`. `ShortcutEngine` starts the app monitor, adapter registry, event tap, menu introspector, and browser bridge. `EventTapManager` installs the global keyboard event tap. `AdapterRegistry` loads built-in, generated, and user adapters. `BrowserBridge` accepts length-prefixed JSON frames over a Unix socket from the Chrome-family native messaging helper.

The existing browser extension resources live under `app/Shorty/Sources/ShortyCore/Resources/BrowserExtension`. They are Chrome-family extension files today. The Safari path should reuse the domain normalization and message shape where possible but must be packaged as a Safari Web Extension target bundled with the macOS app.

The root `justfile` is the command surface. Build and release scripts are under `scripts/tooling`. Python tests cover scripts and static web validation under `tests`. Swift tests live under `app/Shorty/Tests/ShortyCoreTests`.

## Plan of Work

First, make the existing release workflow green. Fix lint blockers, preserve the clean checkout promise, and create this living ExecPlan. Add release model types to `ShortyCore` so the app and tests can express shortcut profiles, conflicts, browser context sources, Safari extension state, update state, support bundles, and release verification results without ad hoc strings.

Second, extend runtime state. `AppMonitor` should remember whether browser context came from Safari or the Chrome bridge so stale web domains are cleared correctly. `ShortcutEngine` should expose setup state, Safari extension status, update status, diagnostic snapshots, and support bundle export. The existing `StatusBarView` and `SettingsView` should gain setup, browser, updates, and diagnostics surfaces while keeping snapshot-driven SwiftUI content views for screenshot generation and tests.

Third, add release and extension scaffolding. Update Tuist to include a Safari Web Extension target and a sandboxed App Store candidate app target. Add resources and Info.plist files for those targets. Add verification scripts that can inspect app bundles and fail clearly if expected extension bundles, signatures, notarization evidence, or DMG contents are missing.

Fourth, improve configuration and adapter workflows. Add user shortcut profile persistence, conflict detection, per-app and per-mapping enablement, adapter revisions, generated adapter review metadata, import/export, and support request scaffolding. Keep behavior conservative for dangerous mappings such as Enter/Submit/Newline.

Fifth, harden reliability and energy. Add bounded serial execution for menu/AX actions, lifecycle recovery hooks, a repeated-failure kill switch, lazy bridge startup where possible, diagnostics timer control, OSLog signposts, and repeatable performance scripts.

Finally, update docs and run verification. The release is acceptable only when root CI, app packaging, DMG packaging, Safari extension verification, release verification, and relevant manual QA instructions are all current and passing or clearly gated on credentials that are not stored in the repo.

## Concrete Steps

Use these commands from `/Users/peyton/.codex/worktrees/034e/shorty` during implementation:

    just web-check
    just lint
    just test-python
    just test-app
    just integration
    just ci
    just app-package VERSION=1.0.0
    just dmg-package VERSION=1.0.0
    just safari-extension-verify
    just release-verify VERSION=1.0.0

Credential-gated commands must fail with clear instructions when required signing or notarization environment variables are absent. They must not silently produce public-release-looking artifacts with ad-hoc signatures.

## Validation and Acceptance

Acceptance requires `just ci` to exit 0 from a clean checkout. `just app-package VERSION=1.0.0` must create a signed zip and checksum under `.build/releases`. `just dmg-package VERSION=1.0.0` must create a DMG with `Shorty.app` and an Applications shortcut. `just release-verify VERSION=1.0.0` must validate checksum, extracted app signature, bundle version, Gatekeeper assessment when possible, Safari extension bundle presence, and notarization/staple status when credentials are supplied.

Launching Shorty must show actionable first-run setup. A user must be able to grant Accessibility, see the active app and matching adapter coverage, enable launch at login, inspect Safari extension status, install or uninstall Chrome-family bridge manifests, edit shortcut profile scaffolding, and export a support bundle.

Swift unit tests must cover the new models and routing logic. Python tests must cover the new release and manifest scripts. UI screenshot generation must still work.

## Idempotence and Recovery

All build outputs go under `.build`, `.DerivedData`, `.cache`, `.state`, or `.venv`. Release scripts must be safe to rerun for the same version. Browser manifest installation must only write the known Shorty manifest file for selected browsers and uninstall must only remove that known file. Support bundle export must write to a user-selected or temp path and redact user-specific paths where practical.

If a release command fails because credentials are missing, rerun after setting the documented environment variables. If Xcode or signing state is wrong, the command should fail before publishing artifacts. If the Safari extension target is unavailable on a local Xcode installation, `safari-extension-verify` should fail clearly and point to the target or bundle path it expected.

## Artifacts and Notes

Important baseline evidence:

    just test-python
    23 passed

    just test-app
    Executed 48 tests, with 0 failures

    just integration
    ui-scripting verified fixture menus

Final verification evidence:

    just ci
    passed

    just app-package VERSION=1.0.0
    Created .build/releases/shorty-1.0.0-macos.zip
    SHA256 9fdc7fcd9d207b114f559cd3022a892cfd5bda6209411ea51050c25d631cbd6f

    just release-verify VERSION=1.0.0
    Release verified

    just safari-extension-verify
    Bundle ID: app.peyton.shorty.SafariWebExtension

    just dmg-package VERSION=1.0.0
    Created .build/releases/shorty-1.0.0-macos.dmg

    just app-store-build && just app-store-validate
    App Store candidate verified

    bash scripts/tooling/appcast_generate.sh --version 1.0.0 --download-url https://example.com/shorty-1.0.0-macos.zip --allow-unsigned
    Created .build/releases/appcast.xml

## Interfaces and Dependencies

Add these Swift types under `app/Shorty/Sources/ShortyCore`:

- `UserShortcutProfile`
- `ShortcutConflict`
- `KeyboardLayoutDescriptor`
- `ShortcutCaptureResult`
- `AdapterReview`
- `AdapterRevision`
- `RuntimeDiagnosticSnapshot`
- `SupportBundle`
- `BridgeInstallStatus`
- `BridgeBrowserTarget`
- `SafariExtensionStatus`
- `BrowserContextSource`
- `ReleaseVerificationResult`
- `UpdateStatus`

Use Sparkle 2 for direct-download update state. Do not include Sparkle in App Store candidate builds. Use Apple SafariServices APIs for Safari extension status and preferences where available. Keep Chrome-family browser support on native messaging manifests. Keep all tooling repo-local through `just`, `mise`, and `uv`.

## Revision Notes

2026-04-14: Created the plan because the user requested implementation of the full backlog with signed Safari extension and secondary App Store path. The plan records the staged approach and the known baseline failures so later implementers can resume without prior conversation context.
