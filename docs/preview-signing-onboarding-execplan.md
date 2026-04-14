# Make Preview Builds Trustworthy and First-Run Setup Visible

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository uses the ExecPlan rules in `~/.agents/PLANS.md`. This document is self-contained for the Shorty changes it describes.

## Purpose / Big Picture

Shorty needs macOS Accessibility permission and a Safari extension app group to work reliably. A downloaded GitHub preview build that is ad-hoc signed has no stable Apple signing identity, fails Gatekeeper assessment, is not notarized, and can confuse macOS privacy permission tracking. After this change, GitHub preview artifacts are produced through a Developer ID signing and notarization path, signing preserves the app and extension entitlements, and first-run setup is visible even if the menu bar icon is hard to find.

The user-visible outcome is that a downloaded preview build can be assessed by Gatekeeper, can keep a stable Accessibility identity across launches for the same signed build lineage, and opens setup on first launch. In Settings, the setup checklist includes Launch at Login alongside Accessibility, Safari, and browser bridge setup.

## Progress

- [x] 2026-04-14T12:50:11Z Inspected the downloaded `Shorty.app` bundle and confirmed it is ad-hoc signed, has no Team ID, fails `spctl`, has no stapled notarization ticket, and has no embedded entitlements.
- [x] 2026-04-14T12:50:11Z Inspected the repo and found `.github/workflows/preview-release.yml` intentionally forces ad-hoc signing for preview releases.
- [x] 2026-04-14T12:59:18Z Preserved entitlements when `scripts/tooling/app_package.sh` signs the Release app bundle.
- [x] 2026-04-14T12:59:18Z Taught `scripts/tooling/app_notarize.sh` and `just app-notarize` to notarize preview-labeled archives without renaming them to the SemVer public-release archive.
- [x] 2026-04-14T12:59:18Z Updated `.github/workflows/preview-release.yml` so preview releases import Developer ID signing material from GitHub Environment secrets, notarize and staple the preview app, verify Gatekeeper/staple status, and publish source artifacts.
- [x] 2026-04-14T12:59:18Z Added first-run setup behavior and a reliable menu bar label in the SwiftUI app.
- [x] 2026-04-14T12:59:18Z Added Launch at Login setup state and controls.
- [x] 2026-04-14T12:59:18Z Updated tests and documentation, then ran focused and full verification commands.
- [x] 2026-04-14T13:08:39Z Simplified GitHub notarization to use the same Team App Store Connect API key model as App Store automation, removing the app-specific-password path.

## Surprises & Discoveries

- Observation: The downloaded app is structurally code-signed but only with an ad-hoc signature.
  Evidence: `codesign -dv --verbose=4 Shorty.app` reported `Signature=adhoc` and `TeamIdentifier=not set`.

- Observation: Gatekeeper and notarization fail for the downloaded preview.
  Evidence: `spctl -a -vvv -t exec Shorty.app` reported `rejected`; `stapler validate Shorty.app` reported no ticket.

- Observation: Manual signing currently strips entitlements.
  Evidence: `codesign -dvvv --entitlements - Shorty.app` and the Safari extension bundle printed signing metadata but no entitlement plist, even though `app/Shorty/Shorty.entitlements` and `app/Shorty/ShortySafariWebExtension.entitlements` exist.

- Observation: The app already stores SwiftUI Settings state, but no first-run completion key was present in defaults.
  Evidence: `defaults read app.peyton.shorty` contained a SwiftUI selected-tab entry and no `Shorty.FirstRun.Complete`.

- Observation: Tuist 4.180 still attempted to refresh a tuist.dev token with only `--cache-profile none`, which broke `just test-app` on this machine.
  Evidence: `just test-app` failed before compilation with `The refreshing of the access and refresh token pair for the URL https://tuist.dev failed after 5 seconds.` Adding `--no-binary-cache` to the repo-local generator let `just test-app` and `just ci` run without a Tuist login.

## Decision Log

- Decision: GitHub preview releases should require Developer ID signing and notarization instead of continuing to publish ad-hoc artifacts.
  Rationale: Shorty depends on macOS privacy and extension behavior where stable signing identity matters. An ad-hoc preview can launch but is not a trustworthy end-user test artifact.
  Date/Author: 2026-04-14 / Codex

- Decision: Preserve entitlements by signing nested code explicitly instead of relying on `codesign --deep --sign`.
  Rationale: `--deep` is coarse and the current command does not pass the app or extension entitlement files, so the Safari app group path is lost.
  Date/Author: 2026-04-14 / Codex

- Decision: Implement Launch at Login through `SMAppService.mainApp` in `ShortyCore`.
  Rationale: The project targets macOS 13 or newer, and `SMAppService.mainApp` is the system API for registering the app itself as a login item.
  Date/Author: 2026-04-14 / Codex

- Decision: Put the preview workflow in a `preview-release` GitHub Environment.
  Rationale: The workflow uses Apple signing and notarization secrets. The repo's zizmor policy requires secrets to be protected by a dedicated GitHub Environment.
  Date/Author: 2026-04-14 / Codex

- Decision: Use Team App Store Connect API key authentication for direct-download notarization in automation.
  Rationale: `xcrun notarytool submit` supports `--key`, `--key-id`, and `--issuer`, so GitHub does not need Apple ID app-specific password secrets when a Team API key is already available.
  Date/Author: 2026-04-14 / Codex

## Outcomes & Retrospective

Implemented the release and onboarding fixes. Local validation cannot prove Developer ID notarization without Apple credentials, but it did prove that ad-hoc local packaging now preserves the app-group entitlement on both `Shorty.app` and `ShortySafariWebExtension.appex`, and the strict release verifier catches missing app-group entitlements. The GitHub path now uses Developer ID signing secrets plus Team App Store Connect API key notarization secrets, without Apple ID app-specific passwords. The full repo `just ci` target passed after the Tuist offline-generation fix.

## Context and Orientation

The macOS app lives under `app/Shorty`. `app/Shorty/Sources/Shorty/ShortyApp.swift` defines the app entry point and menu bar extra. `app/Shorty/Sources/Shorty/SettingsView.swift` defines the Settings tabs, including the current Setup tab. `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift` owns runtime state exposed to the UI. `app/Shorty/Sources/ShortyCore/ReleaseModels.swift` contains Codable status models used by the UI and support bundle.

Release automation lives under `scripts/tooling` and is exposed through the root `justfile`. `scripts/tooling/app_package.sh` builds, signs, and zips `Shorty.app`. `scripts/tooling/app_notarize.sh` submits the zip to Apple notarization, staples the built app, and repackages it. `.github/workflows/preview-release.yml` creates GitHub prerelease artifacts after CI passes on `master`.

Developer ID signing means signing a macOS app with an Apple Developer Program certificate named like `Developer ID Application: Name (TEAMID)`. Notarization means uploading the signed archive to Apple so macOS Gatekeeper can verify Apple scanned and accepted it. A stapled ticket is notarization evidence attached to the app bundle so Gatekeeper can validate it even when offline.

## Plan of Work

First, update `scripts/tooling/app_package.sh` to sign `ShortyCore.framework`, `ShortySafariWebExtension.appex`, and `Shorty.app` explicitly. The app extension must be signed with `app/Shorty/ShortySafariWebExtension.entitlements`; the app must be signed with `app/Shorty/Shorty.entitlements`. The command should keep ad-hoc signing available for local packaging but still apply entitlements.

Second, update `scripts/tooling/app_notarize.sh` and the `justfile` so notarization accepts an optional `ARTIFACT_LABEL`. When a preview archive is named `shorty-preview-abcdef012345-macos.zip`, notarization should submit that archive and repackage the stapled app back to that same preview-labeled archive.

Third, update `.github/workflows/preview-release.yml` to require signing secrets, import a base64-encoded Developer ID `.p12` certificate into a temporary keychain, write a base64-encoded Team App Store Connect API `.p8` key into the runner temp directory, package with `SHORTY_CODESIGN_IDENTITY`, notarize with `SHORTY_APP_STORE_CONNECT_KEY_PATH`, `SHORTY_APP_STORE_CONNECT_KEY_ID`, and `SHORTY_APP_STORE_CONNECT_ISSUER_ID`, run strict release verification against the preview label, and publish the source archive and checksum alongside the app archive and checksum.

Fourth, update `ShortyApp.swift` so the menu bar label uses a system image that the menu bar reliably renders, and so first launch opens Settings to the Setup tab. Update `ShortcutEngine.swift`, `ReleaseModels.swift`, and `SettingsView.swift` to expose Launch at Login status and a setup toggle using `SMAppService.mainApp`.

Fifth, update tests in `tests/test_release_tooling.py` and `app/Shorty/Tests/ShortyCoreTests/ReleaseModelsTests.swift`, then update README documentation for the required GitHub secrets. Run focused Python and Swift tests, then run broader repo verification where practical.

## Concrete Steps

Run commands from the repository root `/Users/peyton/.codex/worktrees/2934/shorty`.

After editing release tooling, run:

    uv run pytest tests/test_release_tooling.py -v

After editing Swift models and UI, run:

    just test-app

Before completion, run:

    just ci

The commands above were run successfully. A local preview package was also created and verified with:

    SHORTY_BUILD_NUMBER=999 just app-package VERSION=1.0.0 ARTIFACT_LABEL=preview-localtest
    just source-package VERSION=1.0.0
    bash scripts/tooling/release_verify.sh --version 1.0.0 --artifact-label preview-localtest --require-codesign

## Validation and Acceptance

The downloaded preview issue is fixed when a newly produced GitHub preview artifact reports a real Team ID from `codesign -dv --verbose=4 Shorty.app`, passes `spctl -a -vvv -t exec Shorty.app`, and passes `stapler validate Shorty.app`. The app and Safari extension must also show the expected application group entitlement when inspected with `codesign -d --entitlements -`.

The onboarding issue is fixed when launching Shorty with no `Shorty.FirstRun.Complete` default opens Settings on the Setup tab, the menu bar item has a visible system image, and Settings includes a Launch at Login control that reflects and changes `SMAppService.mainApp.status`.

Automated acceptance includes Python release tooling tests and Swift app tests passing from the repo root.

## Idempotence and Recovery

The signing and notarization scripts may be rerun. They overwrite the same `.build/releases/shorty-<label>-macos.zip` archive and checksum. The GitHub workflow uses a temporary keychain under `$RUNNER_TEMP`; reruns recreate it. Local ad-hoc packaging remains available by leaving `SHORTY_CODESIGN_IDENTITY` unset or set to `-`, but ad-hoc artifacts should be treated only as local development builds.

The first-run Settings behavior is gated by the existing `Shorty.FirstRun.Complete` user default. Users and testers can reset it in Settings with Reset Setup or by deleting the default.

## Artifacts and Notes

Initial inspection of the downloaded preview produced the important evidence below:

    Signature=adhoc
    TeamIdentifier=not set
    Shorty.app: rejected
    Shorty.app does not have a ticket stapled to it.

Verification after the signing-script fix produced:

    Release verified: .build/releases/shorty-preview-localtest-macos.zip
    Source verified: .build/releases/shorty-1.0.0-source.tar.gz
    just ci exited 0

## Interfaces and Dependencies

`ShortcutEngine` will expose `@Published public private(set) var launchAtLoginStatus: LaunchAtLoginStatus`, plus `setLaunchAtLoginEnabled(_:)` and `refreshLaunchAtLoginStatus()`.

`LaunchAtLoginStatus` will live in `app/Shorty/Sources/ShortyCore/ReleaseModels.swift` and be `Codable` and `Equatable` so it can be included in support state later if needed.

The app uses Apple's `ServiceManagement` framework through `SMAppService.mainApp`, available on the repository's macOS 13 deployment target.

The GitHub workflow expects these `preview-release` Environment secrets: `SHORTY_DEVELOPER_ID_CERTIFICATE_BASE64`, `SHORTY_DEVELOPER_ID_CERTIFICATE_PASSWORD`, `SHORTY_CI_KEYCHAIN_PASSWORD`, `SHORTY_CODESIGN_IDENTITY`, `SHORTY_APP_STORE_CONNECT_KEY_BASE64`, `SHORTY_APP_STORE_CONNECT_KEY_ID`, and `SHORTY_APP_STORE_CONNECT_ISSUER_ID`. The App Store Connect API key must be a Team key, not an Individual key, because this workflow supplies an issuer UUID to `notarytool`.

Revision note 2026-04-14: Created this plan after confirming the downloaded GitHub preview is ad-hoc signed, unnotarized, and entitlement-free, and after identifying first-run setup and Launch at Login gaps in the app UI.

Revision note 2026-04-14: Marked the plan complete after implementing entitlement-preserving signing, preview notarization support, GitHub Environment signing, first-run setup, Launch at Login controls, and the Tuist offline-generation fix.

Revision note 2026-04-14: Updated the completed plan to reflect the simplified App Store Connect API key notarization path and removal of Apple ID app-specific password secrets from GitHub automation.
