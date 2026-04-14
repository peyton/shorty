# Shorty reliability and supportability improvement pass

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository uses the ExecPlan format described in `/Users/peyton/.agents/PLANS.md`. This document is self-contained for the improvement batch requested on 2026-04-14.

## Purpose / Big Picture

The goal of this pass is to turn a broad external improvement review into a focused set of working changes that make Shorty easier to diagnose, safer to configure, and clearer to use. After the work, users should have more actionable Settings screens, exported support bundles should contain enough metadata for troubleshooting, and low-level parsing and validation should reject ambiguous or malformed input before it can affect shortcut behavior.

## Progress

- [x] (2026-04-14T14:44Z) Read repository instructions, project layout, existing app UI, adapter registry, release models, and tests.
- [x] (2026-04-14T14:44Z) Started `claude -p` review request for at least 20 suggested improvements.
- [x] (2026-04-14T14:52Z) Hardened `KeyCombo` parsing and domain normalization with tests.
- [x] (2026-04-14T14:52Z) Added richer support bundle metadata and UI actions for exporting/copying diagnostics.
- [x] (2026-04-14T14:52Z) Improved Settings shortcut and adapter screens with empty states, conflict details, adapter summaries, and validation warning details.
- [x] (2026-04-14T14:52Z) Updated troubleshooting docs for the new diagnostics behavior.
- [x] (2026-04-14T15:00Z) Added bridge read timeouts, stricter adapter identifier validation, and an adapter JSON schema document based on low-risk Claude suggestions.
- [x] (2026-04-14T15:04Z) Ran Python tests, lint, and Swift source type-checks; `xcodebuild` test/build invocations timed out before compilation output and are recorded below.

## Surprises & Discoveries

- Observation: The Settings file already contains older unused tab views after the current consolidated Advanced tab. They are not wired into the active `TabView`, so this pass should avoid expanding them and should keep active UI changes in the currently used tab structures.
  Evidence: `SettingsContentView` uses Setup, Shortcuts, Apps, and Advanced tabs, while `SettingsBrowsersTab`, `SettingsUpdatesTab`, `SettingsDiagnosticsTab`, and `SettingsAboutTab` remain later in the file.
- Observation: `KeyCombo(from:)` accepts the last non-modifier token as the key, which means an input with multiple key tokens can silently ignore earlier tokens.
  Evidence: the parser currently assigns `key = part` in the default branch without rejecting a second key.
- Observation: Support bundles previously exported adapter identifiers and raw diagnostics but not a concise summary of adapter source counts, active availability, or release-facing status.
  Evidence: `SupportBundle` only contained `diagnostics`, `shortcutProfile`, `adapters`, and `notes` before this pass.
- Observation: The first `claude -p` run returned a plan-mode message rather than the requested list. A second plain-text-only run returned 25 suggestions, including Settings refactors, adapter schema docs, support bundle redaction, bridge I/O timeout, and stronger event tap lifecycle behavior.
  Evidence: The second command output numbered 25 items and recommended `BrowserBridge` I/O timeout and adapter JSON schema documentation, both adopted in this pass.

## Decision Log

- Decision: Treat the external review as idea generation and implement a cohesive reliability/supportability slice instead of attempting large speculative features such as full updater integration or in-app bridge installation.
  Rationale: The user explicitly allowed best judgment. This slice improves behavior already present in the repo and can be verified with tests in the current worktree.
  Date/Author: 2026-04-14 / Codex.
- Decision: Keep UI changes within the existing SwiftUI structure and avoid introducing new global services.
  Rationale: The project already owns state in `ShortcutEngine`, snapshot structs, and local SwiftUI state. Reusing those patterns keeps the change reviewable.
  Date/Author: 2026-04-14 / Codex.
- Decision: Copy Diagnostics should copy the same JSON as Export Support Bundle instead of introducing a separate text format.
  Rationale: One canonical diagnostic payload is easier to test, document, and compare across support channels.
  Date/Author: 2026-04-14 / Codex.
- Decision: Defer high-risk or product-sized Claude suggestions such as full Sparkle integration, custom shortcut recording, broad Swift concurrency migration, and large file splits.
  Rationale: They are valid directions, but they are not coherent with this focused pass and would require a larger design/test cycle.
  Date/Author: 2026-04-14 / Codex.

## Outcomes & Retrospective

Implemented the focused supportability slice. Shorty now rejects ambiguous shortcut strings, normalizes URL-like browser domains before web adapter lookup, times out blocked browser bridge reads, validates adapter identifiers more strictly, exports richer support bundle summaries, and gives Settings users copy/export diagnostics, conflict details, adapter source summaries, and expanded adapter warning details. A contributor-facing adapter JSON schema was added. High-risk product work from Claude, such as Sparkle integration and custom shortcut recording, remains intentionally out of scope for a larger dedicated plan.

## Context and Orientation

Shorty is a macOS menu-bar app that translates a fixed set of canonical shortcuts into per-app native shortcuts. The Swift app lives under `app/Shorty/Sources`. `ShortyCore` contains reusable models and engine code such as `AdapterRegistry`, `KeyCombo`, `DomainNormalizer`, `ReleaseModels`, and `ShortcutEngine`. The SwiftUI user interface lives mostly in `app/Shorty/Sources/Shorty/SettingsView.swift` and `StatusBarView.swift`. Swift tests live under `app/Shorty/Tests/ShortyCoreTests`. Python and static site tooling live under `scripts`, `tests`, and `web`.

An adapter is a mapping from one app identifier, such as `com.apple.Safari` or `web:figma.com`, to the shortcut actions Shorty should use in that app. A support bundle is JSON exported from Settings that captures diagnostics, shortcut profile data, adapters, and notes for troubleshooting.

## Plan of Work

First, harden model parsing. In `app/Shorty/Sources/ShortyCore/Models/KeyCombo.swift`, update the human-readable string initializer so it trims whitespace, rejects empty parts, and fails when more than one non-modifier key is present. In `app/Shorty/Sources/ShortyCore/DomainNormalizer.swift`, normalize full URLs, hostnames with ports, trailing dots, and upper-case domains before adapter lookup. Add tests for both behaviors in `app/Shorty/Tests/ShortyCoreTests/KeyComboTests.swift`.

Second, enrich diagnostics. In `app/Shorty/Sources/ShortyCore/ReleaseModels.swift`, add a compact support summary model that records app version, update status, Launch at Login status, adapter counts by source, supported web domains, validation warning count, and active availability. Update `ShortcutEngine.supportBundle()` to populate it. Add tests in `ReleaseModelsTests.swift` that prove the JSON contains the new stable fields.

Third, improve Settings. In `app/Shorty/Sources/Shorty/SettingsView.swift`, add a Copy Diagnostics action alongside Export Support Bundle, show shortcut conflict details, add an all-shortcuts category and empty search state, add adapter source summaries, and expand validation warning details. Keep state local to the view or the existing snapshot/actions types.

Fourth, document the user-visible change in `docs/troubleshooting.md`, especially how to export or copy diagnostics and what information is included.

## Concrete Steps

Run all commands from `/Users/peyton/.codex/worktrees/62bd/shorty`.

Implement code edits with `apply_patch`, then run:

    just test-python
    just test-app
    just lint

If Xcode project generation is required before Swift tests, run:

    just generate

If a full app build is practical after tests, run:

    just build

Validation performed:

    just generate
    # Succeeded; Tuist warned that remote cache authentication is unavailable.

    just test-python
    # 31 passed.

    just lint
    # Passed, including markdown, shell, workflow, Python, web, and SwiftLint checks.

    gtimeout 120 xcrun swiftc -typecheck -target arm64-apple-macos13.0 -parse-as-library $(find app/Shorty/Sources/ShortyCore -name '*.swift' | sort)
    # Succeeded.

    rm -rf .build/typecheck && mkdir -p .build/typecheck && gtimeout 120 xcrun swiftc -emit-module -parse-as-library -target arm64-apple-macos13.0 -module-name ShortyCore -emit-module-path .build/typecheck/ShortyCore.swiftmodule $(find app/Shorty/Sources/ShortyCore -name '*.swift' | sort) && gtimeout 120 xcrun swiftc -typecheck -target arm64-apple-macos13.0 -parse-as-library -I .build/typecheck $(find app/Shorty/Sources/Shorty -name '*.swift' | sort)
    # Succeeded.

    just test-app
    # Attempted twice. Both runs stalled in xcodebuild before any Swift compilation output and were terminated/timeout-limited.

    gtimeout 120 xcodebuild build -workspace app/Shorty.xcworkspace -scheme ShortyCore -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath .DerivedData/build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO COMPILATION_CACHE_ENABLE_CACHING=NO COMPILATION_CACHE_ENABLE_PLUGIN=NO
    # Timed out with BUILD INTERRUPTED before compile diagnostics.

## Validation and Acceptance

The change is accepted when `KeyCombo` rejects ambiguous strings and still parses normal shortcuts, domain normalization handles full URLs and ports, support bundle JSON includes the new summary metadata, Settings compiles with the new actions and panels, and repository tests pass or any environmental blocker is clearly documented.

## Idempotence and Recovery

The parsing and UI changes are ordinary source edits and can be rerun safely. Tests use temporary directories and isolated `UserDefaults` suites where applicable. If a Swift build fails after UI edits, fix the compiler error at the named callsite and rerun the Swift test command before continuing.

## Artifacts and Notes

Claude review output was requested with:

    claude -p "You are reviewing this repository at /Users/peyton/.codex/worktrees/62bd/shorty. Suggest at least 20 concrete features and improvements that would make the project better. Focus on improvements that are implementable in the existing codebase, with emphasis on user-facing quality, reliability, tests, release tooling, docs, and maintainability. For each item, include: title, affected area/files if you can infer them, why it matters, rough implementation notes, and risk/effort. Do not modify files."

The command had not emitted output when this plan was first written, so implementation proceeds from local inspection while keeping the process alive.

## Interfaces and Dependencies

No new third-party dependencies are required. The support bundle additions must remain `Codable` and use existing `JSONEncoder` behavior. The UI additions should use SwiftUI and AppKit already imported by `SettingsView.swift`, including `NSPasteboard` for copying diagnostics.
