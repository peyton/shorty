# Make the menu bar popover live and reliable

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository does not check in `PLANS.md`; this document follows the local `~/.agents/PLANS.md` requirements for self-contained, outcome-focused plans.

## Purpose / Big Picture

Shorty is a macOS menu bar app that translates a user's preferred keyboard shortcuts for the app in front. After this change, opening Shorty's menu bar popover should immediately show the current frontmost app, or the most recently used non-Shorty app when the popover itself has focus, and its available shortcuts should appear without clicking around. A user can see the fix by switching to a supported app such as Safari, opening Shorty's menu bar item, and seeing Safari's shortcut list immediately.

## Progress

- [x] (2026-04-14 19:50Z) Identified the stale popover path: `StatusBarView` observes only `ShortcutEngine`, while frontmost-app and adapter changes publish from nested objects.
- [x] (2026-04-14 19:50Z) Identified the menu activation path: `AppMonitor` updates from `NSWorkspace.didActivateApplicationNotification`, which can report Shorty when the menu bar window is active.
- [x] (2026-04-14 20:10Z) Made `AppMonitor` preserve the last real app when Shorty is activated and expose a testable frontmost-app refresh method.
- [x] (2026-04-14 21:15Z) Made `AppMonitor` clear the active context if the remembered app terminates, so the popover does not show a closed app.
- [x] (2026-04-14 20:15Z) Added `StatusBarSnapshotStore`, which observes engine, app monitor, registry, event tap, and browser bridge publishers.
- [x] (2026-04-14 20:25Z) Added core tests for active-app preservation and refresh injection.
- [x] (2026-04-14 20:35Z) Added SwiftUI popover rendering tests for the available-shortcuts list and no-adapter recovery action.
- [x] (2026-04-14 20:45Z) Wired the new app test target into `app/Shorty/Project.swift` and updated `just test-app` to run both `ShortyCore` and `Shorty`.
- [x] (2026-04-14 20:55Z) Added concise root `AGENTS.md` guidance for future Shorty menu bar test coverage.
- [x] (2026-04-14 21:05Z) Verified `just typecheck-app`, `just test-python`, `just integration`, `just lint`, and `git diff --check`.
- [ ] `just test-app` is blocked in this environment because `xcodebuild` hangs before Swift compilation starts; see `Artifacts and Notes`.

## Surprises & Discoveries

- Observation: `NSRunningApplication` does not expose an activation timestamp, so "most recently used" cannot be reconstructed from `NSWorkspace.shared.runningApplications` alone.
  Evidence: compiling `NSWorkspace.shared.frontmostApplication?.activationDate` fails with "value of type 'NSRunningApplication' has no member 'activationDate'".
- Observation: `SettingsSnapshotStore` already handles nested publishers and coalesced refreshes, so the popover can use the same local store pattern instead of introducing a global state container.
  Evidence: `app/Shorty/Sources/Shorty/SettingsView.swift` observes `engine.appMonitor`, `engine.registry`, `engine.eventTap`, and `engine.browserBridge`.
- Observation: Both Xcode 26.5 beta and Xcode 26.4 hang in `xcodebuild test` and single-target `xcodebuild build` before Swift compilation output.
  Evidence: Commands reached `CreateBuildDescription` and the compiler version probe, then produced no further output for more than one minute. Sampling the process showed `xcodebuild` waiting in `-[Xcode3CommandLineBuildTool waitForBuildWithBuildLog:...]`.
- Observation: "Most recently used app still open" needs termination handling, not only activation filtering.
  Evidence: Without `NSWorkspace.didTerminateApplicationNotification`, a remembered app could remain in `currentBundleID` after quitting while Shorty's popover had focus.

## Decision Log

- Decision: Preserve the last non-Shorty app in `AppMonitor` rather than letting the Shorty menu bar window become the active shortcut context.
  Rationale: The user asked the menu bar to show the frontmost app, or the most recently used app still open, and a menu bar utility should not lose context because its own popover gained focus.
  Date/Author: 2026-04-14 / Codex
- Decision: Add a popover-specific snapshot store modeled after `SettingsSnapshotStore`.
  Rationale: `ShortcutEngine` owns nested observable objects, but SwiftUI only invalidates `StatusBarView` for the object it directly observes. A local store keeps view data fresh without broad engine refactors.
  Date/Author: 2026-04-14 / Codex

## Outcomes & Retrospective

Implemented. The menu bar popover now keeps the last non-Shorty app as context, clears that context when the remembered app quits, refreshes the frontmost app when opened, and observes nested runtime publishers so shortcut availability updates without incidental clicks. Core and SwiftUI rendering tests cover the failure modes. Full `xcodebuild test` execution remains blocked by an Xcode build-service hang in this environment, but direct Swift typechecking, Python tests, macOS integration, lint, and diff checks pass.

## Context and Orientation

The macOS app lives under `app/Shorty`. `app/Shorty/Sources/Shorty/ShortyApp.swift` creates the `MenuBarExtra` and settings scene. `app/Shorty/Sources/Shorty/StatusBarView.swift` renders the menu bar popover from `StatusBarSnapshot.live(engine:)`. `app/Shorty/Sources/Shorty/SettingsView.swift` already uses `SettingsSnapshotStore` to observe nested engine state and rebuild a stable `SettingsSnapshot`. `app/Shorty/Sources/ShortyCore/AppMonitor.swift` owns the current frontmost-app state. `app/Shorty/Sources/ShortyCore/AdapterRegistry.swift` turns an effective app identifier, such as `com.apple.Safari` or `web:figma.com`, into a `ShortcutAvailability` list for the UI.

In this plan, "frontmost app" means the user's active application as reported by macOS through `NSWorkspace`. "Effective app identifier" means the identifier Shorty uses for lookup: a native bundle identifier for normal apps, or a `web:<domain>` identifier when a browser bridge reports a supported web app.

## Plan of Work

First, update `AppMonitor` so it can ignore Shorty's own bundle identifiers. The monitor should keep its previous state when an ignored app activates. It should also expose a `refreshActiveApplication()` method for production and a testable overload that accepts a lightweight app snapshot. `StatusBarView` will call this refresh when the popover appears.

Second, add `StatusBarSnapshotStore` in `StatusBarView.swift`. The store will own the current `StatusBarSnapshot`, observe the engine's published state plus nested `appMonitor`, `registry`, `eventTap`, and optional `browserBridge` publishers, coalesce refreshes on the main queue, and explicitly refresh the active app when the popover opens.

Third, add tests. Core unit tests will cover ignored app activation and refresh behavior. Core integration tests will verify that Safari and web app contexts produce available shortcut lists from the registry. UI rendering tests will import the app target, render `StatusBarContentView` in an `NSHostingView`, and assert the immediately rendered accessibility tree contains the expected app name and shortcut labels. The app test script will run both the existing core tests and the new app UI tests.

Fourth, add a concise root `AGENTS.md` note explaining that changes to menubar status or shortcut availability should update core state tests plus SwiftUI rendering tests.

## Concrete Steps

Run commands from the repository root `/Users/peyton/.codex/worktrees/2221/shorty`.

Use `just generate` after changing `app/Shorty/Project.swift` to regenerate the Xcode workspace. Use `just test-app` to run Swift tests. Use `just test-python` for Python tooling tests. Use `just build` or `just ci-build` after tests to confirm the app still compiles.

## Validation and Acceptance

Acceptance is behavioral. When Safari is active and Shorty's menu bar popover opens, the header says Safari and the "Available now" section lists Safari shortcuts immediately. When Shorty's popover itself has focus, the context remains the last real app rather than switching to Shorty. When a browser bridge reports `figma.com` while Safari is active, the popover shows Figma Web shortcuts.

Automated validation should include `just test-app` when Xcode's build service is healthy. The new `AppMonitor` tests should fail before the monitor ignores Shorty and pass after. The new popover rendering tests should fail before the popover has a fresh snapshot path and pass after. In this environment, `just test-app` is blocked before compilation by an Xcode build-service hang, so `just typecheck-app`, `just test-python`, `just integration`, and `just lint` are the completed verification set.

## Idempotence and Recovery

The changes are additive and safe to rerun. `just generate` can be repeated; it regenerates the workspace from `app/Shorty/Project.swift`. Test result bundles under `.build` and derived data under `.DerivedData` are generated artifacts and can be removed with `just clean-build` if Xcode state becomes stale.

## Artifacts and Notes

Important verification transcripts will be added here after tests run.

Verification evidence from 2026-04-14:

    just typecheck-app
    # exit 0

    just test-python
    # 32 passed in 0.30s

    just integration
    # Built fixture app: .../ShortyFixtureEditor.app
    # Built automation probe: .../AutomationProbe
    # activated app.peyton.shorty.fixture.editor
    # ui-scripting verified fixture menus

    just lint
    # Done linting! Found 0 violations, 0 serious in 35 files.

    git diff --check
    # exit 0

Blocked Xcode evidence:

    DEVELOPER_DIR=/Applications/Xcode-26.4.0.app/Contents/Developer just test-app
    # Reached CreateBuildDescription for ShortyCore and then stopped producing build output.
    # Interrupted after the same hang reproduced on both Xcode 26.5 beta and Xcode 26.4.

## Interfaces and Dependencies

In `app/Shorty/Sources/ShortyCore/AppMonitor.swift`, define a lightweight public snapshot type for active applications and add:

    public func refreshActiveApplication()
    public func refreshActiveApplication(frontmostApplication: ActiveApplicationSnapshot?)

In `app/Shorty/Sources/Shorty/StatusBarView.swift`, add an internal `StatusBarSnapshotStore: ObservableObject` with:

    @Published private(set) var snapshot: StatusBarSnapshot
    func refreshFromFrontmostApplication()

No new third-party dependencies should be added. Tests should use XCTest, AppKit, and SwiftUI only.

Revision note, 2026-04-14 / Codex: Created the initial plan after source inspection so the active-app and stale-SwiftUI issues can be fixed and verified together.

Revision note, 2026-04-14 / Codex: Updated progress, discoveries, outcomes, and artifacts after implementation and verification. Recorded the `xcodebuild` hang because it is the only incomplete acceptance item.
