# Release hardening for Shorty 1.0 direct download

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

The repository instructions refer to `~/.agent/PLANS.md`, but that file is not present in this environment. The available guide is `/Users/peyton/.agents/PLANS.md`; this document follows that guide and is self-contained so a novice can continue the work from only this file and the current working tree.

## Purpose / Big Picture

Shorty is preparing for a public direct-download macOS release. After this work, a user can download a signed package, launch Shorty, understand what permission is needed, see whether Shorty is working for the active app, optionally install the browser bridge, and get help when something fails. A maintainer can run one release preflight, produce a deterministic app package and checksum, optionally notarize it, and verify the app, site, and release tooling from a clean checkout.

This plan hardens two paths. The primary path is native-app shortcut remapping through the macOS Accessibility event tap. The secondary path is the optional browser bridge, which lets Chrome-family browsers report the active web app domain so Shorty can choose a web adapter. The browser bridge remains optional; Shorty must remain useful without it.

## Progress

- [x] 2026-04-14T04:12:53Z Confirmed the baseline `just ci` completed successfully before implementation.
- [x] 2026-04-14T04:12:53Z Confirmed the release target is direct download and the browser bridge should ship as optional.
- [x] 2026-04-14T04:12:53Z Created this living ExecPlan.
- [x] 2026-04-14T05:03:21Z Hardened ShortyCore state, logging, adapter validation, indexed resolution, event tap diagnostics, permission retry, and browser bridge socket/I/O.
- [x] 2026-04-14T05:03:21Z Refined the menu bar popover and Settings UI for release usability.
- [x] 2026-04-14T05:03:21Z Added release packaging, preflight, optional notarization, bridge install/uninstall, and tag artifact CI.
- [x] 2026-04-14T05:03:21Z Updated the static website and troubleshooting docs for direct download, Accessibility, and optional bridge setup.
- [x] 2026-04-14T05:03:21Z Added Swift and Python tests for the changed behavior.
- [x] 2026-04-14T05:44:22Z Ran `just app-package VERSION=1.0.0`, verified archive and checksum under `.build/releases/`, and confirmed the Release bundle reports version `1.0.0` build `1`.
- [x] 2026-04-14T05:45:15Z Ran `just ci`; lint, Python tests, Swift tests, web build, and Release app build passed.
- [x] 2026-04-14T05:46:08Z Ran release preflight with explicit local-test overrides for dirty tree, ad-hoc signing, and beta Xcode; preflight passed for `1.0.0`.
- [x] 2026-04-14 Rebuilt `just app-package VERSION=1.0.0` after fixing archive symlink handling; checksum verification and `codesign --verify --deep --strict` passed on an extracted app.
- [x] 2026-04-14 Reran `just ci` after the packaging and Tuist helper fixes; all checks passed.

## Surprises & Discoveries

- Observation: The repo instructions refer to `~/.agent/PLANS.md`, but that exact path does not exist.
  Evidence: `sed -n '1,260p' /Users/peyton/.agent/PLANS.md` failed with `No such file or directory`; `/Users/peyton/.agents/PLANS.md` exists and was read.
- Observation: The skill paths advertised in the session used an older plugin cache hash.
  Evidence: the listed paths under `.../fb0a183.../skills/.../SKILL.md` were missing; matching skills were found under `.../1f87561.../skills/.../SKILL.md`.
- Observation: Baseline repository verification was green before release hardening started.
  Evidence: `just ci` passed lint, static site validation, Python tests, SwiftLint, Swift unit tests, web build, and Release app build.
- Observation: This local machine is using Xcode 26.5 beta.
  Evidence: `just app-package VERSION=1.0.0` invoked `/Applications/Xcode-26.5.0-Beta.app/.../xcodebuild`; the new release preflight rejects beta Xcode unless `SHORTY_ALLOW_BETA_XCODE=1` is set.
- Observation: Zip archive creation must preserve symlink metadata before considering whether a path is a directory.
  Evidence: package verification found framework links such as `Versions/Current` and `Resources` could be expanded incorrectly; `package_app.py` now writes symlink entries with Unix metadata, and the extracted app passes `codesign --verify --deep --strict`.

## Decision Log

- Decision: Optimize for public direct download, not Mac App Store distribution.
  Rationale: The current app uses a global keyboard event tap and optional Chrome native messaging, both of which fit direct distribution better than an App Store sandbox review path.
  Date/Author: 2026-04-14 / Codex
- Decision: Ship the browser bridge as optional.
  Rationale: Native-app shortcut remapping is the core release path, while web-app support should be hardened and documented without blocking app usefulness.
  Date/Author: 2026-04-14 / Codex
- Decision: Keep release tooling repo-local and explicit.
  Rationale: The repo instructions forbid runtime dependency installation and prefer standard runners such as `just`, `mise`, and `uv`.
  Date/Author: 2026-04-14 / Codex

## Outcomes & Retrospective

Release hardening is implemented. The app now exposes user-facing engine,
permission, bridge, and event-tap status; starts the engine from app lifecycle;
persists the Enabled toggle; retries Accessibility permission checks; validates
adapters before load/save; uses indexed shortcut resolution; hides raw
diagnostics behind disclosure UI; and keeps generated adapters explicit for
release.

Release tooling now provides `just release-preflight`, `just app-package
VERSION=...`, `just app-notarize VERSION=...`, and `just release VERSION=...`.
Local packaging created `.build/releases/shorty-1.0.0-macos.zip` and
`.build/releases/shorty-1.0.0-macos.zip.sha256`; the checksum verified from the
release directory.

Verification passed with `just web-check`, `just lint`, `just app-package
VERSION=1.0.0`, checksum verification, bundle version inspection, `just ci`,
and release preflight with explicit local-test overrides. Public release still
requires a clean git tree, a stable non-beta Xcode, and a real Developer ID
signing identity unless explicit local-test overrides are set.

A package verification pass caught and fixed framework symlink preservation in
the deterministic zip writer. The final `.build/releases/shorty-1.0.0-macos.zip`
extracts with framework symlinks intact, the checksum file verifies, and the
extracted app passes deep strict codesign verification.

## Context and Orientation

The repository root is `/Users/peyton/.codex/worktrees/5d2f/shorty`. `justfile` is the primary command surface. `mise.toml` pins tools. `pyproject.toml` and `uv.lock` define Python validation dependencies. The macOS app is under `app/` and is generated by Tuist from `app/Shorty/Project.swift`. The static public website is under `web/`. Python tooling lives under `scripts/` and tests under `tests/`.

The main Swift targets are:

- `Shorty`, the menu-bar app in `app/Shorty/Sources/Shorty`.
- `ShortyCore`, the framework in `app/Shorty/Sources/ShortyCore`.
- `ShortyBridge`, the command-line native messaging shim in `app/Shorty/Sources/ShortyBridge/main.swift`.
- `ShortyCoreTests`, the Swift unit tests in `app/Shorty/Tests/ShortyCoreTests`.

Important terms:

- A canonical shortcut is the key combination a user wants to press everywhere, represented by `CanonicalShortcut`.
- An adapter maps canonical shortcut IDs to the app-specific action needed by the active app, represented by `Adapter`.
- An event tap is a macOS input hook created by `CGEvent.tapCreate`; Shorty uses it to observe and rewrite keyboard events after the user grants Accessibility permission.
- The browser bridge is optional. A Chrome-family extension sends the active domain to `ShortyBridge`; that shim forwards the native messaging frame to Shorty's Unix socket, and `BrowserBridge` updates `AppMonitor.webAppDomain`.

## Plan of Work

First, add release-state types to ShortyCore and wire them into `ShortcutEngine`, `EventTapManager`, `AdapterRegistry`, and `BrowserBridge`. Use `OSLog` instead of `print`, make permission state explicit, persist the enabled toggle, avoid automatic adapter generation by default, validate adapters before loading or saving, and build a precomputed adapter lookup for efficient key handling.

Second, revise SwiftUI surfaces in `StatusBarView.swift`, `SettingsView.swift`, and `ShortyApp.swift`. The menu bar popover should lead with status and next action, not raw diagnostics. Advanced details such as bundle IDs, adapter source, and event counters should be behind a disclosure. Settings should make shortcuts and adapters searchable, show version/build from the bundle, and expose explicit adapter generation instead of silently writing generated adapters.

Third, harden the browser bridge. Move the socket path into Application Support with safe directory creation, support partial writes and interrupted system calls, report structured status, validate and debounce extension domains, and add installer support for multiple Chrome-family manifest directories plus uninstall.

Fourth, add release tooling. Add `just release-preflight`, `just app-package VERSION=...`, `just app-notarize VERSION=...`, and `just release VERSION=...`. The package command must build a Release app, verify the bundle version matches the requested version, create a deterministic zip or tar archive under `.build/releases/`, and write a SHA-256 checksum. Notarization must be explicit and must fail clearly when required credentials are missing.

Fifth, update the website and docs for the direct-download release path. The web copy must explain download/checksum, Accessibility permission, optional browser bridge setup, support, privacy, and troubleshooting. The existing static site validator must continue to pass.

Finally, add tests and run verification. Add Swift tests for adapter validation, indexed resolution, engine defaults, bridge protocol helpers, and domain filtering. Add Python tests for release packaging/preflight and browser manifest install/uninstall path generation. Run `just ci` and `just app-package VERSION=1.0.0`.

## Concrete Steps

Work from the repository root:

    cd /Users/peyton/.codex/worktrees/5d2f/shorty

Use these commands during implementation:

    just test-python
    just test-app
    just web-check
    just ci
    just app-package VERSION=1.0.0

When editing Swift project structure, regenerate before building:

    just generate

Expected successful release-package evidence:

    Created .build/releases/shorty-1.0.0-macos.zip
    Created .build/releases/shorty-1.0.0-macos.zip.sha256
    SHA256 <64 lowercase hex characters>

## Validation and Acceptance

Acceptance requires all of the following:

`just ci` exits 0. The existing lint, web, Python, Swift test, web build, and Release build shards all pass.

`just app-package VERSION=1.0.0` exits 0 and creates a deterministic app archive and checksum under `.build/releases/`. Re-running the command without source changes produces the same checksum when the app bundle contents are unchanged.

Launching Shorty without Accessibility permission shows an actionable permission state with buttons to open Accessibility settings and check again. After permission is granted, the user can retry without quitting.

The Enabled toggle persists across app restarts. When disabled, Shorty does not remap shortcuts and the UI explains that state.

For a supported app with an adapter, the popover shows Shorty is active and displays coverage in user-facing language. For an unsupported app, the popover shows pass-through behavior without implying an error.

Adapter JSON loaded from user or auto-generated directories is validated before use. Invalid adapters are skipped with a logged validation reason and do not crash the app.

The browser bridge is optional. If it is not installed or Shorty is not running, the app still works for native adapters and bridge tooling reports clear errors. If installed, supported domains are reported and unsupported domains are ignored by default.

## Idempotence and Recovery

All release scripts must be safe to rerun. Build outputs go under `.build/` and `.DerivedData/`, both ignored by Git. Browser bridge install writes native messaging manifests outside the repo only when explicitly requested. The uninstall command removes only the known Shorty native messaging manifest filenames from selected browser manifest directories.

If `just ci` fails, fix the first actionable compile, lint, or test error and rerun the failing shard before rerunning full CI. If notarization fails, the package artifact should remain available so credentials or Apple service issues can be retried without rebuilding unless the app changed.

## Artifacts and Notes

Baseline verification before implementation:

    just ci
    ...
    ** BUILD SUCCEEDED **

The exact full output was long, but the process exited with status 0.

## Interfaces and Dependencies

Add these public ShortyCore types:

- `EngineStatus`: describes startup, running, disabled, permission needed, failed, and stopped states in user-facing terms.
- `PermissionState`: describes whether Accessibility permission is granted.
- `BrowserBridgeStatus`: describes stopped, listening, failed, connected/recent-message state for the optional bridge.
- `AdapterValidationError`: describes why an adapter JSON file or value is unsafe or malformed.
- `EngineConfiguration`: holds release-safe toggles such as whether menu introspection auto-generation is enabled and whether all browser domains are reported.

Extend `AdapterRegistry` with validated loading/saving and indexed resolution while preserving the current adapter JSON shape.

Add or update repo-local scripts under `scripts/tooling/` and expose them through `justfile`. Use existing pinned tooling through `mise`, `uv`, and shell scripts; do not add runtime dependency installation to the app.
