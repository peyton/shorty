# Daily-use hardening audit and implementation pass

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository follows `/Users/peyton/.agents/PLANS.md`. This document is self-contained for the daily-use hardening audit requested on 2026-04-14.

## Purpose / Big Picture

Shorty should become a quiet menu-bar utility that a user trusts every day. The app already translates canonical shortcuts for supported native apps and web apps, but daily use depends on accurate status, understandable setup, conservative generated adapters, visible browser bridge state, explicit pause controls, and diagnostics that explain what happened without requiring a developer. This pass records the audit and implements the daily-use hardening items that fit the existing architecture without adding heavyweight dependencies or runtime installers.

## Progress

- [x] (2026-04-14T16:05:38Z) Read repository instructions and `/Users/peyton/.agents/PLANS.md`.
- [x] (2026-04-14T16:05:38Z) Audited the app entry point, status popover, settings UI, shortcut engine, event tap, browser bridge, adapter registry, release models, tests, docs, and tooling.
- [x] (2026-04-14T16:05:38Z) Attempted Claude Code as requested. The first non-interactive run hung without output; the second non-interactive run with `--permission-mode bypassPermissions` returned a usage-limit error.
- [x] (2026-04-14T16:20:00Z) Reviewed independent fallback subagent proposals and recorded accepted high-value items in `docs/daily-use-audit.md`.
- [x] (2026-04-14T16:20:00Z) Implemented the first daily-use hardening slice: honest event counters, bridge install-status inspection, generated-adapter review metadata, direct update binding, and dead Settings tab removal.
- [x] (2026-04-14T16:35:00Z) Ran Python tests, lint, and direct Swift source type-checks. `just test-app` and `just build` both stalled in Xcode before compile diagnostics and were terminated; details recorded below.
- [x] (2026-04-14T17:10:00Z) Continued the implementation across the reviewed proposal set: thread-safe app/adapter snapshots, context guards, bounded menu invocation, browser bridge hardening, shortcut/profile editing, adapter import/export/delete/toggles, pause controls, App Store candidate runtime limits, diagnostics redaction, and support tooling.
- [x] (2026-04-14T17:33:18Z) Added remaining small safety items: repeated event-tap startup backoff and keyboard-layout capture display.
- [x] (2026-04-14T17:33:18Z) Re-ran `just typecheck-app`, `just test-python`, `just lint`, `git diff --check`, and `just adapter-coverage-audit`. Native `just test-app` and `just build` were retried with `gtimeout 240` and timed out in Xcode build planning/tool setup.
- [x] (2026-04-14T17:50:04Z) Re-ran Claude Code after access was restored, reviewed its findings, implemented confirmed follow-ups, and re-ran verification. `gtimeout 240 just test-app` still timed out in Xcode build planning before compiler output.

## Surprises & Discoveries

- Observation: Claude Code is installed, but unavailable for this run because the account is at its usage limit.
  Evidence: `/Users/peyton/.local/bin/claude -p ...` returned `You've hit your limit · resets 11am (America/Los_Angeles)`.
- Observation: Claude Code became available later in the same session and confirmed broad coverage while identifying a handful of worthwhile follow-ups.
  Evidence: The second Claude run completed with ordered findings; confirmed fixes were applied for event-tap flag synchronization, context guard strictness, adapter revision persistence, bridge socket reuse, menu traversal deadline computation, exact-domain extension matching, and extension/domain parity tests.
- Observation: The active Settings UI uses four tabs, but older private tab structs were still in the same file before this pass and were not wired into `SettingsContentView`.
  Evidence: `SettingsContentView` creates Setup, Shortcuts, Apps, and Advanced tabs; the unused `SettingsBrowsersTab`, `SettingsUpdatesTab`, `SettingsDiagnosticsTab`, and `SettingsAboutTab` structs were removed in this pass.
- Observation: `BridgeInstallStatus`, `BridgeBrowserTarget`, `AdapterReview`, `AdapterRevision`, `KeyboardLayoutDescriptor`, and `ShortcutCaptureResult` existed as release-facing models, but several were not wired into the app's visible daily workflow.
  Evidence: This pass wires bridge status, adapter review metadata, adapter revisions, shortcut capture, keyboard layout display, and support-bundle diagnostics.
- Observation: The previous event counter labeled "intercepted" only incremented after a canonical shortcut resolved. Ordinary keyDown events seen by the event tap were not counted.
  Evidence: `EventTapManager` now separates key events seen, matched shortcuts, remaps, pass-throughs, menu/AX attempts, menu/AX outcomes, and context guards.

## Decision Log

- Decision: Implement the daily-use proposals that fit the current codebase and explicitly defer only large structural work or dependency choices.
  Rationale: The reviewed proposals mixed runtime safety, diagnostics, Settings workflows, release setup, tests, and structural refactors. This pass prioritizes behavior users feel every day while avoiding a broad file split, adapter catalog migration, Sparkle integration, or a native bridge installer without a separate design.
  Date/Author: 2026-04-14 / Codex.
- Decision: Treat Claude Code output as unavailable, not as optional hidden context.
  Rationale: The tool returned a concrete usage-limit error. Fabricating Claude's review would make the audit less trustworthy.
  Date/Author: 2026-04-14 / Codex.
- Decision: Use existing state ownership patterns: `ShortcutEngine` owns runtime state, snapshot structs feed SwiftUI, and Settings actions stay thin.
  Rationale: This matches the current codebase and avoids adding global services or a second state architecture.
  Date/Author: 2026-04-14 / Codex.

## Outcomes & Retrospective

Implementation is complete for the daily-use hardening pass. The resulting app now has thread-safe shortcut resolution snapshots, clearer runtime diagnostics, conservative context guards, bounded menu invocation, bridge protocol and manifest hardening, generated-adapter review gates, persisted shortcut customization, adapter enable/delete/import/export controls, per-app/global pause flows, keyboard layout capture context, App Store candidate runtime limits, redacted support diagnostics, a troubleshooting guide, and repo-local typecheck/adapter-audit tooling.

Python tests, lint, direct Swift type-checks, diff whitespace checks, and the adapter coverage audit passed. Full Xcode test/build commands still stall before compiler diagnostics in this environment; no Swift source errors were found by direct type-checks.

The remaining intentionally deferred items are structural or dependency decisions rather than missing daily behavior: splitting the large SwiftUI files, moving the built-in adapter catalog to generated data/modules, wiring a real Sparkle updater, adding service abstractions for deterministic engine tests, and replacing copyable bridge install commands with a native installer flow.

## Context and Orientation

Shorty is a macOS menu-bar app. The SwiftUI entry point is `app/Shorty/Sources/Shorty/ShortyApp.swift`. The menu-bar popover is `app/Shorty/Sources/Shorty/StatusBarView.swift`. The settings window is `app/Shorty/Sources/Shorty/SettingsView.swift`. Core runtime logic is under `app/Shorty/Sources/ShortyCore`, especially `ShortcutEngine.swift`, `EventTapManager.swift`, `AdapterRegistry.swift`, `BrowserBridge.swift`, `ReleaseModels.swift`, and `ShortcutAvailability.swift`.

An adapter maps a native app bundle identifier such as `com.apple.Safari`, or a web identifier such as `web:figma.com`, to actions Shorty should use for canonical shortcuts. A generated adapter is an adapter made by reading the active app's macOS menus through Accessibility. The browser bridge is the optional Chrome-family Native Messaging path that lets a browser extension tell Shorty which web app domain is active.

## Local Audit Proposals

The following local proposals are grounded in the current code. They are intentionally phrased as necessary features, fixes, or improvements, not speculative gimmicks.

1. Fix event tap counters so "key events seen" counts every enabled keyDown event and "matched shortcuts" counts resolved Shorty shortcuts. Anchor: `EventTapManager.swift`, `StatusBarView.swift`, `SettingsView.swift`.
2. Add separate counters for remap, passthrough, menu invoke, and AX action outcomes. Anchor: `EventTapManager.swift`, `RuntimeDiagnosticSnapshot`.
3. Dispatch menu and AX actions through one serial queue to avoid concurrent Accessibility tree walks. Anchor: `EventTapManager.swift`.
4. Add last action metadata for diagnostics: active app, canonical ID, native action kind, and timestamp. Anchor: `EventTapManager.swift`, `ReleaseModels.swift`.
5. Add a repeated-failure backoff or safe mode when tap recreation fails repeatedly. Anchor: `ShortcutEngine.swift`, `EventTapManager.swift`.
6. Add a clear tap-disabled lifecycle state with user-visible recovery notes. Anchor: `RuntimeStatus.swift`, `StatusBarView.swift`.
7. Expire stale browser domains after no bridge or Safari message for a short interval. Anchor: `AppMonitor.swift`, `BrowserBridge.swift`, `SafariExtensionBridge.swift`.
8. Show browser bridge install status for each Chrome-family browser using the existing `BridgeInstallStatus` model. Anchor: `ReleaseModels.swift`, `ShortcutEngine.swift`, `SettingsView.swift`.
9. Add copyable install and uninstall commands for the browser bridge from Settings. Anchor: `SettingsActions`, `AdvancedBrowsersSection`.
10. Add Chrome extension ID validation in app UI before showing bridge install commands. Anchor: `SettingsView.swift`, `browser_manifest.py` parity.
11. Show the browser bridge socket path and helper path in diagnostics only when expanded. Anchor: `BrowserBridge.swift`, `SettingsView.swift`.
12. Detect missing bridge executable separately from missing browser manifests. Anchor: `BridgeInstallStatus`.
13. Detect malformed browser native messaging manifests and report actionable fixes. Anchor: `BridgeInstallStatus`, tests.
14. Add Safari extension last-message age and stale-state warning. Anchor: `SafariExtensionStatus`, `SettingsView.swift`.
15. Replace "manual update checks will appear here" with either a real update check or no fake update affordance. Anchor: `AdvancedUpdatesSection`, `SettingsActions`.
16. Fix `AdvancedUpdatesSection` so the toggle cannot drift from the latest `UpdateStatus`. Anchor: `SettingsView.swift`.
17. Remove obsolete unused Settings tab structs to reduce compile and review surface. Anchor: `SettingsView.swift`.
18. Split `SettingsView.swift` into smaller files by tab or section after the first pass. Anchor: `app/Shorty/Sources/Shorty`.
19. Split `StatusBarView.swift` into snapshot/actions/content files after the first pass. Anchor: `app/Shorty/Sources/Shorty`.
20. Add user-visible success feedback for Copy Diagnostics and Export Support Bundle. Anchor: `SettingsActions`, `SettingsSnapshot`.
21. Redact user-specific paths or mark local paths explicitly in support bundles. Anchor: `SupportBundle`, `RuntimeDiagnosticSnapshot`.
22. Include bridge install status in support bundles. Anchor: `SupportBundleSummary`.
23. Include generated adapter review confidence and warnings in support bundles. Anchor: `AdapterReview`, `SupportBundle`.
24. Add generated-adapter review metadata before saving: confidence, reasons, warnings, and mapping count. Anchor: `ShortcutEngine.swift`, `SettingsView.swift`.
25. Save generated adapter revisions when a generated adapter is accepted. Anchor: `AdapterRevision`, `ShortcutEngine.swift`.
26. Add UI to view adapter revision history for generated and user adapters. Anchor: `SettingsAdaptersTab`.
27. Add a generated-adapter diff against any existing adapter before overwrite. Anchor: `AdapterRegistry.swift`, `SettingsView.swift`.
28. Add a delete generated adapter action. Anchor: `AdapterRegistry.swift`, `SettingsAdaptersTab`.
29. Add per-adapter enable/disable state so users can pause one app without disabling Shorty globally. Anchor: `AdapterRegistry`, settings model.
30. Add per-mapping enable/disable state for risky mappings such as Enter and Shift-Enter. Anchor: `Adapter.Mapping`, `UserShortcutProfile`.
31. Add custom shortcut profile editing and persistence; current profile is effectively static. Anchor: `UserShortcutProfile`, `ShortcutEngine.swift`, Settings Shortcuts tab.
32. Add shortcut capture UI using the existing `ShortcutCaptureResult` model. Anchor: `SettingsShortcutsTab`.
33. Add keyboard layout display and warnings using the existing `KeyboardLayoutDescriptor`. Anchor: `KeyCombo.swift`, `SettingsShortcutsTab`.
34. Add warnings for known macOS-reserved shortcuts; the enum case exists but detection does not. Anchor: `ShortcutConflict.detect`.
35. Add a conflict resolution UI rather than only listing conflicts. Anchor: `SettingsShortcutsTab`.
36. Add context guards for submit/newline mappings so Shorty does not surprise users outside text entry. Anchor: `EventTapManager.swift`, `Adapter.Mapping.context`.
37. Add an explicit "dangerous mapping" review step for mappings that swallow Return, Space, or Command-W. Anchor: `AdapterReview`, `SettingsAdaptersTab`.
38. Add local app coverage audit tooling that suggests adapters from installed recent apps without telemetry. Anchor: `scripts/tooling`, `AdapterRegistry`.
39. Add search by native key combo and canonical key combo in the Apps tab. Anchor: `SettingsAdaptersTab`.
40. Add coverage scoring per app: native, remapped, generated, risky, unavailable. Anchor: `ShortcutAvailability.swift`.
41. Add a compact daily-use mode in the popover and keep raw diagnostics collapsed. Anchor: `StatusBarView.swift`.
42. Add keyboard navigation and accessibility identifiers for the popover and Settings controls. Anchor: SwiftUI views and screenshot tests.
43. Add screenshot or UI smoke tests for the active Settings tabs after visual changes. Anchor: `ShortyScreenshots`, tests.
44. Add a faster Swift type-check command to CI for source-only PR feedback. Anchor: `justfile`, scripts.
45. Add tests for event tap metric semantics without requiring a live global event tap. Anchor: `EventTapManager` pure helper or metrics type.
46. Add tests for bridge install-status detection using a temporary home directory. Anchor: `BridgeInstallStatus`, `ReleaseModelsTests`.
47. Add tests for generated-adapter review warnings. Anchor: `ShortcutEngine` or a pure review helper.
48. Add structured, localized copy for status titles/details to prevent drift. Anchor: `RuntimeStatus.swift`, SwiftUI.
49. Add error recovery actions in UI where an error is displayed, not only raw details. Anchor: `SettingsView.swift`, `StatusBarView.swift`.
50. Add launch-at-login approval deep link or clearer instruction when macOS returns `requiresApproval`. Anchor: `LaunchAtLoginStatus`, Setup tab.
51. Add a pause duration, such as "pause until tomorrow" or "pause for this app", if users need a reversible escape hatch. Anchor: `ShortcutEngine`, Settings.
52. Add deterministic adapter source precedence display so users know when a user adapter overrides a built-in. Anchor: `AdapterRegistry`, Apps tab.
53. Add symlink and file-count hardening for adapter directories. Anchor: `AdapterRegistry.loadAdapters`.
54. Add import/export of user adapters with validation summary. Anchor: `AdapterRegistry`, Settings Apps tab.
55. Add release build verification that Settings has no dead tabs or unused release models. Anchor: lint or Swift tests.
56. Add app restart guidance when Accessibility trust is stuck. Anchor: `StatusBarView.swift`, `docs/troubleshooting.md`.
57. Add first-run completion feedback when the user presses Done. Anchor: `SettingsSetupTab`.
58. Add "what Shorty will do for this app" wording that distinguishes native pass-through from remapping. Anchor: `ShortcutAvailability`.
59. Add explicit privacy text in app near browser bridge and diagnostics export. Anchor: `AdvancedBrowsersSection`, `AdvancedDiagnosticsSection`.
60. Add performance signposts around event resolution and AX action dispatch. Anchor: `EventTapManager.swift`, `ShortyLog`.

## Plan of Work

First, implement honest event metrics. Add a small diagnostics model or additional counters to `EventTapManager`, increment keyDown events before shortcut resolution, and increment match/remap/action counters after resolution. Update status popover, settings diagnostics, support bundle models, and tests to use the clearer naming.

Second, implement bridge install visibility without invoking package managers or Xcode from the app. Add a Swift helper that inspects expected native messaging manifest paths and the expected helper executable path, returns `[BridgeInstallStatus]`, and includes it in `SettingsSnapshot` and support bundles. Add UI rows under Advanced > Browsers and copyable repo-local `just` commands for install/uninstall.

Third, wire generated adapter review metadata. Add a pure review helper that creates `AdapterReview` from generated mappings, expose it from `ShortcutEngine`, show confidence/reasons/warnings in the generated preview, and store accepted generated revisions in memory for diagnostics.

Fourth, fix Settings state and maintenance debt. Replace the update toggle's local `@State` copy with a binding to the latest snapshot and delete obsolete unused tab structs.

Fifth, run verification and update this plan with actual outputs.

## Concrete Steps

Run all commands from `/Users/peyton/.codex/worktrees/0436/shorty`.

Use `apply_patch` for source edits. After implementation, run:

    just test-python
    just test-app
    just lint
    just build

If `just test-app` or `just build` is too slow in this environment, run source type-checks and record the blocker:

    just generate
    xcrun swiftc -typecheck ...

Validation performed:

    just typecheck-app
    # Passed after Claude follow-up changes.

    just test-python
    # 32 passed.

    just lint
    # Passed; SwiftLint found 0 violations in 34 files.

    git diff --check
    # Passed.

    just adapter-coverage-audit
    # Passed; local scan reported 88 adapters and 104 installed apps without adapters.

    gtimeout 240 just test-app
    # Timed out in xcodebuild build planning/tool setup before compiler output, including after the Claude follow-up changes.

    gtimeout 240 just build
    # Timed out in xcodebuild build planning/tool setup before compiler output.

## Validation and Acceptance

The implementation pass is accepted when source type-checks pass, Python tests still pass, lint is clean, and the UI exposes clearer diagnostics: key events seen, shortcut matches, translated actions, bridge install status, pause state, shortcut customization, and generated adapter review warnings. Support bundle JSON must include the new daily-use diagnostics without breaking existing encoded fields.

## Idempotence and Recovery

All edits are ordinary source and docs changes. Bridge install-status inspection must be read-only. Copying install commands to the pasteboard must not write manifests or build helpers. Tests must use temporary directories and isolated `UserDefaults` suites.

## Artifacts and Notes

Claude Code attempts:

    /Users/peyton/.local/bin/claude -p "..."
    # hung without output

    /Users/peyton/.local/bin/claude -p --output-format text --permission-mode bypassPermissions --tools Read,Grep,Glob,LS,Bash --max-budget-usd 2 "..."
    # You've hit your limit · resets 11am (America/Los_Angeles)

## Interfaces and Dependencies

No new third-party dependencies are required. Use SwiftUI, AppKit, Foundation, and existing ShortyCore models. Do not run Python or shell installers from inside the app. Keep browser bridge management commands as explicit user-triggered copyable commands unless a later plan designs a native installer flow.
