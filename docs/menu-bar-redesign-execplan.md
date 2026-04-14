# Shorty Menu Bar and Flow Redesign

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document follows the rules in `/Users/peyton/.agents/PLANS.md`. It is intentionally self-contained so a new contributor can continue the work from the current working tree alone.

## Purpose / Big Picture

Shorty is a macOS menu bar app that translates one set of keyboard shortcuts into native per-app actions. The current menu bar popover makes users read diagnostics before they can tell whether Shorty is working, which app is active, or which shortcuts are available. After this change, clicking the menu bar item should immediately answer those questions and guide the user through any required Accessibility permission without a manual refresh button.

The redesign keeps the existing shortcut engine intact. It adds a small availability model that turns the active adapter into user-facing rows, makes Accessibility permission re-check itself while missing, and simplifies settings into the few sections users need most often.

## Progress

- [x] (2026-04-14T13:35:25Z) Read existing SwiftUI status/settings code, shortcut engine, adapter registry, screenshot target, and repo workflow.
- [x] (2026-04-14T13:35:25Z) Created this ExecPlan before implementation edits.
- [x] (2026-04-14T13:56:03Z) Added shortcut availability and display-status models with tests.
- [x] (2026-04-14T13:56:03Z) Added automatic Accessibility permission polling and retry.
- [x] (2026-04-14T13:56:03Z) Replaced the menu bar glyph and redesigned the popover around task-relevant information.
- [x] (2026-04-14T13:56:03Z) Simplified Settings into Setup, Shortcuts, Apps, and Advanced.
- [x] (2026-04-14T13:56:03Z) Updated screenshot fixtures and regenerated committed screenshots.
- [x] (2026-04-14T13:56:03Z) Ran required validation commands and recorded outcomes.

## Surprises & Discoveries

- Observation: `SettingsSnapshotStore` already reacts to many engine publishers, so Settings can become more automatic without adding a new app-wide state container.
  Evidence: `SettingsView.swift` observes engine status, permission, Safari extension, launch-at-login, app monitor, event tap counters, registry adapters, and validation messages.
- Observation: The screenshot target already renders `SettingsContentView` and `StatusBarContentView`, so visual acceptance can be preserved by updating fixtures rather than adding a new screenshot tool.
  Evidence: `app/Shorty/Sources/ShortyScreenshots/main.swift` renders native popover/settings screenshots and web/App Store images.
- Observation: A baseline `just test-app` run generated the workspace but emitted no build output for about six minutes and was interrupted during planning.
  Evidence: the interrupted command printed `** BUILD INTERRUPTED **` after `xcodebuild test ... -scheme ShortyCore`.
- Observation: The first screenshot regeneration caught two fixture issues: the new settings layout was wider than the old fixture frame, and first-run setup state redirected Shortcuts/Apps screenshots back to Setup.
  Evidence: `native-settings-shortcuts.png` and `native-settings-apps.png` initially clipped left content, then rendered the Setup tab until the fixture used completed setup state.
- Observation: The final `just test-app` run no longer hung and completed the expanded Swift suite quickly.
  Evidence: `just test-app` reported `** TEST SUCCEEDED **` with 60 tests.

## Decision Log

- Decision: Keep the redesign within the existing SwiftUI files and `ShortyCore` framework rather than adding a new UI framework or runtime dependency.
  Rationale: The app already has SwiftUI views, fixture-based screenshot rendering, and enough engine state to support the requested flows.
  Date/Author: 2026-04-14 / Codex
- Decision: Add a pure availability model in core rather than constructing shortcut rows directly in SwiftUI.
  Rationale: The same data is needed by the popover, settings, screenshots, support tests, and future UI surfaces; testing it in core keeps UI code simpler.
  Date/Author: 2026-04-14 / Codex
- Decision: Use polling only while Accessibility permission is missing or just requested.
  Rationale: macOS Accessibility trust does not publish a reliable app-level notification, but permanent polling would be wasteful.
  Date/Author: 2026-04-14 / Codex

## Outcomes & Retrospective

Implemented the menu bar and settings redesign. The popover now leads with plain status, active app/context, a coverage badge, available shortcut rows with symbolic key badges, translated native actions, a secondary pause/resume control, a conditional permission banner, and collapsed Details diagnostics. Accessibility permission prompting now starts a one-second poll while permission is missing and retries event-tap installation automatically after approval.

Settings now uses four tabs: Setup, Shortcuts, Apps, and Advanced. Setup surfaces positive access state and avoids a primary manual completion/reset flow. Apps leads with current app coverage, renames adapter generation to Add Current App, hides it when Accessibility is missing, sorts the active adapter first, and uses calm source labels. Browser setup, updates, reset setup, diagnostics, and About copy moved into Advanced.

Validation completed successfully:

    just generate
    just test-app
    uv run pytest tests -v
    just lint
    just build
    just marketing-screenshots

Remaining manual acceptance: launch with `just run`, click the menu bar item, and test the live macOS Accessibility approval loop on a machine where Shorty does not already have Accessibility access.

## Context and Orientation

The relevant app code lives under `app/Shorty/Sources`. `ShortyApp.swift` defines the menu bar extra and settings scene. `StatusBarView.swift` renders the menu bar popover. `SettingsView.swift` renders the settings window. `ShortyBrand.swift` contains shared visual components such as `ShortyMenuBarGlyph`, `ShortyPanel`, and `ShortcutKeyBadge`.

The runtime engine lives in `app/Shorty/Sources/ShortyCore`. `ShortcutEngine.swift` owns app monitoring, adapter lookup, the keyboard event tap, browser bridge, Safari extension status, launch-at-login status, and permission checks. `AdapterRegistry.swift` loads adapters and resolves canonical shortcuts to native actions. `Models/CanonicalShortcut.swift` defines the user-facing shortcut names, default key combos, and categories. `Models/Adapter.swift` defines app-specific mappings.

The screenshot target lives at `app/Shorty/Sources/ShortyScreenshots/main.swift`. It renders SwiftUI fixtures to PNGs under `web/assets/screenshots`.

An adapter is Shorty's per-app translation table. A canonical shortcut is the key combo the user wants to press everywhere, such as "Find in Page". A mapping is the adapter entry that says how that canonical shortcut behaves in a specific app, such as pass through, remap to another key combo, invoke a menu item, or perform an Accessibility action.

## Plan of Work

First, add `AvailableShortcut` and `ShortcutAvailability` to `ShortyCore` and expose `AdapterRegistry.availability(for:displayName:)`. This method should return an empty state when no adapter exists and an ordered list of shortcuts when an adapter exists. Each row must contain the canonical name, default keys, category, mapping method, native action summary, and source adapter details.

Second, add a small pure status presentation helper that maps engine status, permission state, user-enabled state, and permission polling into labels such as "Ready", "Paused", and "Needs Accessibility access". Add core tests for these models before wiring them into SwiftUI.

Third, update `ShortcutEngine` so `openAccessibilitySettings()` prompts macOS and starts a short-lived permission monitor. When permission becomes granted, the engine should stop polling and retry installing the event tap automatically. Preserve `checkAccessibilityAndRetry()` for compatibility, but the redesigned UI should not expose a refresh button.

Fourth, replace the popover content in `StatusBarView.swift`. The new popover should have a stable vertical layout with a header, a conditional permission banner, a current-app shortcut list, one pause/resume switch, a collapsed details disclosure, and footer buttons. It should include task-relevant data first and keep diagnostic identifiers hidden until expanded.

Fifth, simplify `SettingsView.swift` to four top-level tabs: Setup, Shortcuts, Apps, and Advanced. Setup should show clear permission and launch-at-login states, Shortcuts should keep canonical shortcut browsing, Apps should show active/current app coverage first and rename adapter generation to "Add Current App", and Advanced should contain browsers, updates, diagnostics, reset setup, about, and support export.

Sixth, update screenshot fixtures for ready, permission-needed, paused, and no-adapter states. Regenerate committed screenshots only after the Swift app builds.

## Concrete Steps

Run commands from `/Users/peyton/.codex/worktrees/f302/shorty`.

Use repo-local runners:

    just generate
    just test-app
    uv run pytest tests -v
    just lint
    just build
    just marketing-screenshots

During implementation, use smaller focused commands when needed, but finish with the full commands above or document why any could not complete.

## Validation and Acceptance

Core tests must prove that adapter availability is correct for known adapters, missing adapters, web identifiers, and each mapping method. Status presentation tests must prove that running, paused, failed, permission missing, permission waiting, and unknown permission states produce the intended user-facing labels.

Manual acceptance requires launching with `just run`, clicking the menu bar item, and seeing the active app plus available shortcuts without using a refresh button. With Accessibility permission missing, the popover must show one clear permission action, wait visibly after the action is clicked, and update automatically once macOS grants permission.

The screenshot command must update the native popover and settings images without clipped text.

## Idempotence and Recovery

All changes are additive or replacements inside tracked source files. Running `just generate` is safe and regenerates the Tuist workspace. Screenshot regeneration overwrites known committed PNG files under `web/assets/screenshots`; inspect them before committing. If `just test-app` appears to hang again, inspect the xcodebuild log at `.build/test-app.xcodebuild.log`, terminate only the command for this workspace, and record the failure in this ExecPlan.

## Artifacts and Notes

Planning baseline:

    uv run pytest tests -v
    31 passed in 0.46s

Interrupted planning baseline:

    just test-app
    ** BUILD INTERRUPTED **
    error: Recipe `test-app` was terminated on line 24 by signal 15

## Interfaces and Dependencies

No new runtime dependencies are allowed. Keep macOS deployment target at 13.0.

In `ShortyCore`, define public types equivalent to:

    public struct AvailableShortcut: Codable, Equatable, Identifiable
    public struct ShortcutAvailability: Codable, Equatable
    public enum AvailableShortcutActionKind: String, Codable
    public struct EngineDisplayStatus: Codable, Equatable

`AdapterRegistry` must expose:

    public func availability(for appID: String?, displayName: String?) -> ShortcutAvailability

`ShortcutEngine` must expose:

    @Published public private(set) var isWaitingForAccessibilityPermission: Bool
    public func openAccessibilitySettings()

These interfaces are consumed by `StatusBarSnapshot`, `SettingsSnapshot`, screenshot fixtures, and tests.
