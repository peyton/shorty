# Marketing screenshots and web polish

This ExecPlan is a living document. The sections `Progress`, `Surprises &
Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to
date as work proceeds.

The repository instructions refer to `~/.agent/PLANS.md`, but that file is not
present in this environment. This document follows the existing ExecPlan style
in `docs/` and is self-contained for the current task.

## Purpose / Big Picture

Shorty needs deterministic public-release marketing assets without interrupting
the user's Mac session. After this work, a maintainer can run
`just marketing-screenshots` from a clean checkout to render native app states
into PNGs for the static website and Mac App Store-compatible 2880x1800
screenshots. The website should use those native screenshots, explain the
local-first shortcut translation story, and pass static validation.

## Progress

- [x] Added a `ShortyScreenshots` command-line target to the Tuist project.
- [x] Refactored Settings and menu bar status views into runtime wrappers plus
      deterministic content views.
- [x] Added an offscreen SwiftUI/AppKit renderer that writes native, web, and
      App Store PNG exports.
- [x] Added `just marketing-screenshots` and PNG dimension validation.
- [x] Updated the static homepage to use product screenshots, local-first copy,
      skip links, and visible focus states.
- [x] Run final app, web, screenshot, and Python verification.

## Surprises & Discoveries

- Observation: `~/.agent/PLANS.md` is not present.
  Evidence: reading that path returned `no ~/.agent/PLANS.md`.
- Observation: A Swift file named `main.swift` cannot also use a separate
  `@main` type.
  Evidence: the screenshot target failed with `'main' attribute cannot be used
  in a module that contains top-level code`; switching to normal top-level
  startup code fixed compilation.
- Observation: The command-line target needs an explicit framework search path
  when launched from the script.
  Evidence: the built tool failed to load `ShortyCore.framework` until
  `DYLD_FRAMEWORK_PATH` was set to the Release products directory.
- Observation: The local `agent-browser` CLI is not installed in this
  environment.
  Evidence: invoking `agent-browser --help` returned `command not found`; web
  visual inspection used an offscreen `WKWebView` snapshot script instead.

## Decision Log

- Decision: Use native offscreen SwiftUI/AppKit rendering instead of live
  desktop capture.
  Rationale: The user explicitly asked for screenshots that do not disturb
  their computer use, and deterministic fixture states are better marketing
  source material.
  Date/Author: 2026-04-14 / Codex
- Decision: Keep the website static HTML/CSS.
  Rationale: The current web stack is dependency-light and the plan explicitly
  avoids adding a hidden browser or runtime dependency.
  Date/Author: 2026-04-14 / Codex

## Plan of Work

First, split runtime SwiftUI wrappers from reusable content views. Keep
`SettingsView` and `StatusBarView` observing `ShortcutEngine`, while exposing
snapshot-driven content views for the renderer.

Second, add a `ShortyScreenshots` command-line target that depends on
`ShortyCore`, imports the two content view files, renders fixed fixture states
with `NSHostingView`, and writes PNGs into `web/assets/screenshots/`.

Third, add repo-local automation through `just marketing-screenshots`. The
script must generate the workspace, build the target, run the renderer, and
validate every exported PNG dimension.

Fourth, polish `web/` around the generated screenshots. Replace the icon-only
hero, improve local-first copy, fix mobile overflow risks, add skip links and
visible `:focus-visible` styles, and preserve the existing static validator
contract.

Finally, verify with the requested root commands and inspect the generated
screenshots and site at desktop and mobile widths.

## Validation and Acceptance

Acceptance requires:

- `just generate` exits 0.
- `just build` exits 0.
- `just test-app` exits 0.
- `just marketing-screenshots` exits 0 and validates PNG dimensions.
- `just web-check` exits 0.
- `just test-python` exits 0.
- The generated screenshots are shown in the thread for visual inspection.

## Outcomes & Retrospective

Implemented the offscreen screenshot workflow and refreshed the homepage around
the generated product assets. The native screenshot target exports raw UI states,
three 2880x1800 Mac App Store compositions, and web-sized variants without
opening the app, taking desktop captures, or requiring Accessibility prompts.

Final verification passed with `just generate`, `just build`, `just test-app`,
`just marketing-screenshots`, `just web-check`, and `just test-python`. The
homepage was also visually inspected at desktop and mobile widths with offscreen
`WKWebView` snapshots.
