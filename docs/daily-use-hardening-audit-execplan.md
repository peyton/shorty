# Daily-use hardening audit and first implementation pass

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository follows `/Users/peyton/.agents/PLANS.md`. This document is self-contained for the daily-use hardening audit requested on 2026-04-14.

## Purpose / Big Picture

Shorty should become a quiet menu-bar utility that a user trusts every day. The app already translates canonical shortcuts for supported native apps and web apps, but daily use depends on accurate status, understandable setup, conservative generated adapters, visible browser bridge state, and diagnostics that explain what happened without requiring a developer. This pass records a broad audit and implements the first coherent slice: make status counters honest, remove stale Settings code, show browser bridge install status, add generated-adapter review metadata, and keep verification green.

## Progress

- [x] (2026-04-14T16:05:38Z) Read repository instructions and `/Users/peyton/.agents/PLANS.md`.
- [x] (2026-04-14T16:05:38Z) Audited the app entry point, status popover, settings UI, shortcut engine, event tap, browser bridge, adapter registry, release models, tests, docs, and tooling.
- [x] (2026-04-14T16:05:38Z) Attempted Claude Code as requested. The first non-interactive run hung without output; the second non-interactive run with `--permission-mode bypassPermissions` returned a usage-limit error.
- [x] (2026-04-14T16:20:00Z) Reviewed independent fallback subagent proposals and recorded accepted high-value items in `docs/daily-use-audit.md`.
- [x] (2026-04-14T16:20:00Z) Implemented the first daily-use hardening slice: honest event counters, bridge install-status inspection, generated-adapter review metadata, direct update binding, and dead Settings tab removal.
- [x] (2026-04-14T16:35:00Z) Ran Python tests, lint, and direct Swift source type-checks. `just test-app` and `just build` both stalled in Xcode before compile diagnostics and were terminated; details recorded below.

## Surprises & Discoveries

- Observation: Claude Code is installed, but unavailable for this run because the account is at its usage limit.
  Evidence: `/Users/peyton/.local/bin/claude -p ...` returned `You've hit your limit · resets 11am (America/Los_Angeles)`.
- Observation: The active Settings UI uses four tabs, but older private tab structs were still in the same file before this pass and were not wired into `SettingsContentView`.
  Evidence: `SettingsContentView` creates Setup, Shortcuts, Apps, and Advanced tabs; the unused `SettingsBrowsersTab`, `SettingsUpdatesTab`, `SettingsDiagnosticsTab`, and `SettingsAboutTab` structs were removed in this pass.
- Observation: `BridgeInstallStatus`, `BridgeBrowserTarget`, `AdapterReview`, `AdapterRevision`, `KeyboardLayoutDescriptor`, and `ShortcutCaptureResult` exist as release-facing models, but several were not wired into the app's visible daily workflow.
  Evidence: This pass wired bridge status and adapter review metadata; keyboard layout and shortcut capture remain follow-up items.
- Observation: The current event counter labeled "intercepted" only increments after a canonical shortcut resolves. Ordinary keyDown events seen by the event tap are not counted.
  Evidence: `EventTapManager.handleEvent` calls `recordEvent` only inside the resolved action switch, after the `registry.resolve` guard.

## Decision Log

- Decision: Record the full audit but implement a focused first milestone rather than attempting dozens of product-sized features in one unsafe batch.
  Rationale: The user's request asks for at least 100 proposals and implementation. Implementing all of them at once would mix major UI, security, update, adapter, shortcut customization, and release systems. A coherent, tested slice gives immediate daily-use value and leaves the full backlog explicit.
  Date/Author: 2026-04-14 / Codex.
- Decision: Treat Claude Code output as unavailable, not as optional hidden context.
  Rationale: The tool returned a concrete usage-limit error. Fabricating Claude's review would make the audit less trustworthy.
  Date/Author: 2026-04-14 / Codex.
- Decision: Use existing state ownership patterns: `ShortcutEngine` owns runtime state, snapshot structs feed SwiftUI, and Settings actions stay thin.
  Rationale: This matches the current codebase and avoids adding global services or a second state architecture.
  Date/Author: 2026-04-14 / Codex.

## Outcomes & Retrospective

Implementation is complete for the first milestone. The resulting app now has clearer runtime diagnostics, read-only browser bridge manifest status, generated-adapter review warnings, and less stale Settings code. Python tests, lint, and direct Swift type-checks passed. Full Xcode test/build commands stalled before compiler diagnostics in this environment; no Swift source errors were found by direct type-checks.

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

    just test-python
    # 31 passed.

    just lint
    # Passed; SwiftLint found 0 violations in 34 files.

    rm -rf .build/typecheck && mkdir -p .build/typecheck && xcrun swiftc -emit-module -parse-as-library -target arm64-apple-macos13.0 -module-name ShortyCore -emit-module-path .build/typecheck/ShortyCore.swiftmodule $(find app/Shorty/Sources/ShortyCore -name '*.swift' | sort)
    # Passed.

    xcrun swiftc -typecheck -target arm64-apple-macos13.0 -parse-as-library -I .build/typecheck $(find app/Shorty/Sources/Shorty -name '*.swift' | sort)
    # Passed.

    xcrun swiftc -typecheck -target arm64-apple-macos13.0 -I .build/typecheck $(find app/Shorty/Sources/ShortyBridge -name '*.swift' | sort)
    # Passed.

    xcrun swiftc -typecheck -target arm64-apple-macos13.0 -I .build/typecheck $(find app/Shorty/Sources/ShortyScreenshots -name '*.swift' | sort) app/Shorty/Sources/Shorty/ShortyBrand.swift app/Shorty/Sources/Shorty/SettingsView.swift app/Shorty/Sources/Shorty/StatusBarView.swift
    # Passed.

    just test-app
    # Interrupted after stalling in xcodebuild build planning before compiler output.

    just build
    # Interrupted after stalling in xcodebuild build planning before compiler output.

## Validation and Acceptance

The first milestone is accepted when the app compiles, Swift tests cover new pure helpers, Python tests still pass, lint is clean, and the UI exposes clearer diagnostics: key events seen, shortcut matches, translated actions, bridge install status, and generated adapter review warnings. Support bundle JSON must include the new daily-use diagnostics without breaking existing encoded fields.

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
