# Shorty Daily-Use Audit

Date: 2026-04-14

Claude Code was requested as the independent reviewer. The first local `claude` CLI run was blocked by a rate limit: `You've hit your limit · resets 11am (America/Los_Angeles)`, so I used a read-only fallback subagent with the same prompt and reviewed its output against the codebase. After Claude access was restored, I ran Claude Code again against the implemented repo, reviewed its findings, and applied the confirmed issues. This document keeps both proposal sets concrete and anchored so the backlog is actionable.

## Local Staff-Level Proposals

1. P0: Make event tap reads thread-safe by resolving against immutable app/adapter snapshots instead of reading mutable `AppMonitor` and `AdapterRegistry` state on the tap thread. Anchor: `app/Shorty/Sources/ShortyCore/EventTapManager.swift`.
2. P0: Protect `AdapterRegistry.actionIndex` behind a lock or atomic copy-on-write snapshot so adapter saves cannot race event resolution. Anchor: `app/Shorty/Sources/ShortyCore/AdapterRegistry.swift`.
3. P0: Enforce context guards for Return, Shift-Return, Space, and Command-W before intercepting them. Anchor: `app/Shorty/Sources/ShortyCore/EventTapManager.swift`.
4. P0: Add success/failure telemetry for menu and AX actions so swallowed shortcuts cannot fail silently. Anchor: `app/Shorty/Sources/ShortyCore/EventTapManager.swift`.
5. P0: Invoke menu items by stored menu path, not title alone, to avoid duplicate-title mistakes. Anchor: `app/Shorty/Sources/ShortyCore/MenuIntrospector.swift`.
6. P0: Bound AX menu traversal by depth, item count, and time. Anchor: `app/Shorty/Sources/ShortyCore/MenuIntrospector.swift`.
7. P1: Keep separate counters for key events seen, shortcut matches, remaps, pass-throughs, menu actions, and AX actions. Anchor: `app/Shorty/Sources/ShortyCore/EventTapManager.swift`.
8. P1: Flush pending event counters before exporting a support bundle. Anchor: `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift`.
9. P1: Add bridge install status inspection for each Chrome-family browser. Anchor: `app/Shorty/Sources/ShortyCore/BrowserBridgeInstallManager.swift`.
10. P1: Show bridge manifest status in Settings and support bundles. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
11. P1: Add explicit bridge install/uninstall guidance with copyable commands and extension-ID validation. Anchor: `scripts/tooling/install_browser_bridge.sh`.
12. P1: Redact user home paths from exported diagnostics unless the user explicitly chooses full diagnostics. Anchor: `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`.
13. P1: Clear stale browser context when unsupported domains are reported, instead of leaving the last supported app active. Anchor: `app/Shorty/Sources/ShortyCore/BrowserBridge.swift`.
14. P1: Expire browser context after a TTL without extension messages. Anchor: `app/Shorty/Sources/ShortyCore/AppMonitor.swift`.
15. P1: Generate browser extension supported-domain lists from `DomainNormalizer`. Anchor: `app/Shorty/Sources/ShortyCore/Resources/BrowserExtension/background.js`.
16. P1: Narrow browser extension content-script matches away from `<all_urls>` where feasible. Anchor: `app/Shorty/Sources/ShortyCore/Resources/BrowserExtension/manifest.json`.
17. P1: Use Safari extension state APIs for real enabled/disabled/missing status. Anchor: `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift`.
18. P1: Show last Safari message age and stale warnings. Anchor: `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`.
19. P1: Add generated-adapter review confidence, reasons, warnings, and coverage. Anchor: `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift`.
20. P1: Persist generated adapter revisions for rollback. Anchor: `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`.
21. P1: Gate generated adapters with dangerous mappings before save. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
22. P1: Show match reason and menu path for each generated mapping. Anchor: `app/Shorty/Sources/ShortyCore/IntentMatcher.swift`.
23. P1: Tighten `IntentMatcher` so exact key combo alone cannot match unrelated menu items. Anchor: `app/Shorty/Sources/ShortyCore/IntentMatcher.swift`.
24. P1: Add denylist guards for destructive aliases such as “close all.” Anchor: `app/Shorty/Sources/ShortyCore/IntentMatcher.swift`.
25. P1: Persist `UserShortcutProfile` to disk. Anchor: `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift`.
26. P1: Build shortcut capture/edit UI from `ShortcutCaptureResult`. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
27. P1: Add per-shortcut enable/disable toggles. Anchor: `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`.
28. P1: Add per-app pause and pause-for-duration controls. Anchor: `app/Shorty/Sources/Shorty/StatusBarView.swift`.
29. P1: Add per-mapping enable/disable in adapters. Anchor: `app/Shorty/Sources/ShortyCore/Models/Adapter.swift`.
30. P1: Implement `macOSReserved` conflict detection. Anchor: `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`.
31. P1: Warn when generated/user adapters shadow built-ins. Anchor: `app/Shorty/Sources/ShortyCore/AdapterRegistry.swift`.
32. P1: Add UI to delete generated/user adapters. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
33. P1: Add adapter import/export with validation preview. Anchor: `app/Shorty/Sources/ShortyCore/AdapterRegistry.swift`.
34. P1: Add success feedback for Copy Diagnostics and Export Support Bundle. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
35. P1: Hide update toggles until Sparkle is real, or wire Sparkle fully. Anchor: `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift`.
36. P1: Refresh Launch at Login status whenever Settings opens or app activates. Anchor: `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift`.
37. P1: Show distribution mode in diagnostics: direct download, debug, or App Store candidate. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
38. P1: Add browser message protocol version and tab/window metadata. Anchor: `app/Shorty/Sources/ShortyCore/BrowserBridge.swift`.
39. P1: Make browser bridge socket state thread-safe. Anchor: `app/Shorty/Sources/ShortyCore/BrowserBridge.swift`.
40. P1: Reduce browser bridge max message size to a protocol-sized limit. Anchor: `app/Shorty/Sources/ShortyCore/BrowserBridge.swift`.
41. P1: Validate socket path length in `ShortyBridge` before `strncpy`. Anchor: `app/Shorty/Sources/ShortyBridge/main.swift`.
42. P2: Remove unused Settings tab structs. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
43. P2: Split Settings into setup, shortcuts, adapters, advanced, and shared files. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
44. P2: Bind update toggle directly to `UpdateStatus`. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
45. P2: Default Shortcuts to All Shortcuts or clearly label active category. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
46. P2: Add accessibility identifiers for UI automation. Anchor: `app/Shorty/Sources/Shorty/StatusBarView.swift`.
47. P2: Add keyboard focus management in Settings lists and save/discard controls. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
48. P2: Open Settings directly to generated preview after “Add Current App” from the popover. Anchor: `app/Shorty/Sources/Shorty/StatusBarView.swift`.
49. P2: Move the built-in adapter catalog out of `AdapterRegistry` into generated JSON or smaller modules. Anchor: `app/Shorty/Sources/ShortyCore/AdapterRegistry.swift`.
50. P2: Add app-specific caveats for terminals, password managers, browsers, and chat apps. Anchor: `app/Shorty/Sources/Shorty/SettingsView.swift`.
51. P2: Add non-global unit tests for event metric semantics. Anchor: `app/Shorty/Tests/ShortyCoreTests`.
52. P2: Add tests for bridge install-status parsing. Anchor: `app/Shorty/Tests/ShortyCoreTests`.
53. P2: Add tests for generated adapter review warnings. Anchor: `app/Shorty/Tests/ShortyCoreTests`.
54. P2: Add screenshot smoke tests for all active Settings tabs. Anchor: `app/Shorty/Sources/ShortyScreenshots/main.swift`.
55. P2: Abstract Accessibility and Launch-at-Login services for deterministic engine tests. Anchor: `app/Shorty/Sources/ShortyCore/ShortcutEngine.swift`.

## Independent Review Proposals

The fallback reviewer produced 65 proposals. I reviewed them and found the following priorities actionable:

1. P0: Make event-tap reads thread-safe. Anchor: `EventTapManager.swift`, `AdapterRegistry.swift`.
2. P0: Protect `AdapterRegistry.actionIndex` with atomic snapshots. Anchor: `AdapterRegistry.swift`.
3. P0: Add context guards before intercepting Return, Shift-Return, Space, and Command-W. Anchor: `EventTapManager.swift`.
4. P0: Split event diagnostics by observed, matched, remapped, menu, AX, and pass-through. Anchor: `EventTapManager.swift`.
5. P0: Add success/failure outcomes for menu and AX actions. Anchor: `EventTapManager.swift`.
6. P0: Dispatch menu/AX work on one serial queue with backpressure. Anchor: `EventTapManager.swift`.
7. P0: Invoke menu items by menu path, not only title. Anchor: `MenuIntrospector.swift`.
8. P0: Add recursion, depth, and time limits to menu walking. Anchor: `MenuIntrospector.swift`.
9. P1: Add tap failure backoff/safe mode. Anchor: `ShortcutEngine.swift`.
10. P1: Flush diagnostics before support export. Anchor: `ShortcutEngine.swift`.
11. P1: Add bridge install status manager. Anchor: `ReleaseModels.swift`.
12. P1: Surface per-browser bridge status. Anchor: `SettingsView.swift`.
13. P1: Add in-app install/uninstall guidance. Anchor: `install_browser_bridge.sh`.
14. P1: Validate Chrome extension ID in the app before showing install instructions. Anchor: `browser_manifest.py`.
15. P1: Include bridge install statuses in support bundles. Anchor: `ReleaseModels.swift`.
16. P1: Redact local user paths from support bundles. Anchor: `ShortcutEngine.swift`.
17. P1: Put bridge socket/helper paths under expanded diagnostics with copy controls. Anchor: `BrowserBridge.swift`.
18. P1: Expire stale browser domains. Anchor: `AppMonitor.swift`.
19. P1: Clear browser context on unsupported domain messages. Anchor: `BrowserBridge.swift`.
20. P1: Synchronize browser extension supported domains with `DomainNormalizer`. Anchor: `background.js`.
21. P1: Replace `<all_urls>` content-script scope where possible. Anchor: `manifest.json`.
22. P1: Use `SFSafariExtensionManager.getStateOfSafariExtension`. Anchor: `ShortcutEngine.swift`.
23. P1: Show Safari last-message age. Anchor: `ReleaseModels.swift`.
24. P1: Add generated adapter confidence, reasons, warnings, and mapping count. Anchor: `SettingsView.swift`.
25. P1: Persist accepted generated adapter revisions. Anchor: `ReleaseModels.swift`.
26. P1: Add generated-adapter dangerous mapping gates. Anchor: `MenuIntrospector.swift`.
27. P1: Show match reason/source menu path per generated mapping. Anchor: `IntentMatcher.swift`.
28. P1: Tighten `IntentMatcher` exact-key behavior. Anchor: `IntentMatcher.swift`.
29. P1: Add denylist/semantic guards for destructive aliases. Anchor: `IntentMatcher.swift`.
30. P1: Persist `UserShortcutProfile`. Anchor: `ShortcutEngine.swift`.
31. P1: Build real shortcut capture/edit UI. Anchor: `ReleaseModels.swift`.
32. P1: Add per-shortcut and per-app enable/disable controls. Anchor: `SettingsView.swift`.
33. P1: Add per-mapping enable/disable. Anchor: `Adapter.swift`.
34. P1: Implement `macOSReserved` conflict detection. Anchor: `ReleaseModels.swift`.
35. P1: Add pause-for-this-app and pause-for-N-minutes. Anchor: `StatusBarView.swift`.
36. P1: Warn when user/auto adapters shadow built-ins. Anchor: `AdapterRegistry.swift`.
37. P1: Add UI to delete/disable generated and user adapters. Anchor: `SettingsView.swift`.
38. P1: Add import/export adapter workflow. Anchor: `AdapterRegistry.swift`.
39. P1: Add success feedback for diagnostic copy/export. Anchor: `SettingsView.swift`.
40. P1: Add active Check for Updates button or remove dead action. Anchor: `SettingsView.swift`.
41. P1: Hide update controls until Sparkle exists or wire Sparkle. Anchor: `ShortcutEngine.swift`.
42. P1: Refresh Launch at Login status on activation/settings open. Anchor: `ShortcutEngine.swift`.
43. P1: Add clearer instructions for Launch at Login approval. Anchor: `ShortcutEngine.swift`.
44. P1: Make App Store target explicitly limited for event-tap/bridge flows. Anchor: `Project.swift`.
45. P1: Show distribution mode in About/Diagnostics. Anchor: `SettingsView.swift`.
46. P1: Add browser protocol version/source/window/tab metadata. Anchor: `BrowserBridge.swift`.
47. P1: Make `BrowserBridge` listener state thread-safe. Anchor: `BrowserBridge.swift`.
48. P1: Reduce bridge max message size. Anchor: `BrowserBridge.swift`.
49. P1: Add path-length validation in `ShortyBridge`. Anchor: `ShortyBridge/main.swift`.
50. P1: Add bridge uninstall/status into Settings. Anchor: `justfile`.
51. P2: Remove obsolete Settings tab structs. Anchor: `SettingsView.swift`.
52. P2: Split `SettingsView.swift` into feature files. Anchor: `SettingsView.swift`.
53. P2: Fix update toggle drift. Anchor: `SettingsView.swift`.
54. P2: Default Shortcuts tab to All Shortcuts or add clearer context. Anchor: `SettingsView.swift`.
55. P2: Add accessibility identifiers. Anchor: `StatusBarView.swift`.
56. P2: Add keyboard navigation/focus management. Anchor: `SettingsView.swift`.
57. P2: Handoff no-adapter popover action directly to generated preview review. Anchor: `StatusBarView.swift`.
58. P2: Move hardcoded adapters to generated JSON/fixtures or smaller modules. Anchor: `AdapterRegistry.swift`.
59. P2: Add app-specific notes/caveats. Anchor: `SettingsView.swift`.
60. P2: Add event metric tests without a live event tap. Anchor: `ShortyCoreTests`.
61. P2: Add bridge install-status tests. Anchor: `ShortyCoreTests`.
62. P2: Add generated adapter review tests. Anchor: `ShortyCoreTests`.
63. P2: Add UI/screenshot smoke tests. Anchor: `ShortyScreenshots/main.swift`.
64. P2: Abstract permission and login services for tests. Anchor: `ShortcutEngine.swift`.
65. P2: Add performance signposts around event resolution, AX dispatch, adapter generation, and bridge messages. Anchor: `EventTapManager.swift`.

## Implemented In This Pass

- Removed obsolete Settings tab structs.
- Bound automatic update UI directly to `UpdateStatus`.
- Surfaced bridge manifest status in Settings and support bundles.
- Added generated adapter confidence/reasons/warnings and revision tracking.
- Used split event counters in diagnostics and status details.
- Added tests for event counters, bridge install status parsing, and generated adapter review.
- Added immutable app/adapter resolution snapshots so the event tap no longer reads mutable registry/app-monitor state directly.
- Added per-action success/failure diagnostics, last-action metadata, context-guard counts, and performance signposts.
- Added a repeated event-tap startup failure backoff that pauses retries temporarily instead of failing in a tight loop.
- Added menu-path based invocation with depth/count/time traversal limits.
- Added browser bridge protocol metadata, message-size limits, socket state locking, unsupported-domain clearing, and stale browser context expiry.
- Replaced browser extension `<all_urls>` host access with explicit supported web-app domains.
- Added per-shortcut editing, capture, enable/disable, reset, macOS-reserved conflict detection, and keyboard layout display.
- Added persisted shortcut profile state for shortcut, adapter, and mapping disables.
- Added per-app pause, global pause, pause-until-tomorrow, and resume controls in Settings and the status popover.
- Added adapter search by canonical/native/menu metadata, per-adapter enable/disable, per-mapping enable/disable, delete, import, and export.
- Added generated-adapter dangerous mapping approval gates, match reasons, menu paths, and revision history.
- Added app-specific caveats for terminals, browsers, password managers, and chat-style apps.
- Added App Store candidate runtime configuration that avoids starting the event tap and browser bridge.
- Added redacted diagnostics/support bundle paths and distribution mode in diagnostics.
- Added copyable bridge install/uninstall command guidance with extension ID validation.
- Added `just typecheck-app` and `just adapter-coverage-audit` repo-local tooling.
- Added `docs/troubleshooting.md` for permissions, browser bridge, Safari extension, generated adapters, and support bundle guidance.
- Re-consulted Claude Code after access was restored and applied the confirmed follow-ups: synchronized the event-tap enable flag, invalidated the Mach port on stop, tightened risky built-in remaps to require explicit context, reduced false-positive generated menu matches, persisted adapter revisions, reused the native bridge socket for a host session, optimized menu traversal deadlines, and added browser domain parity tests.

## Deferred After Review

The following proposals were intentionally left as follow-up architecture/dependency work rather than merged into this pass: splitting large SwiftUI files, moving the built-in adapter catalog out of `AdapterRegistry`, wiring a real Sparkle updater, replacing copyable bridge commands with a native installer, and adding deterministic service abstractions plus screenshot automation around Xcode. The current behavior is hardened without those structural changes.
