# Shorty Monorepo Conversion ExecPlan

This ExecPlan is the living record for converting Shorty into a monorepo. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` current as implementation proceeds. This document follows the ExecPlan guidance in `/Users/peyton/.agents/PLANS.md`.

## Purpose / Big Picture

Shorty currently has a small Swift package layout at the repository root. After this change, the repository has a stable monorepo shape: the macOS app lives in `app/`, the static public website lives in `web/`, documentation lives in `docs/`, automation lives in `scripts/`, and all common development commands run from the root through pinned tools. A contributor can clone the repository, run `just bootstrap`, then use `just generate`, `just test`, `just web-check`, `just lint`, and `just ci` without relying on ad hoc global setup.

## Progress

- [x] (2026-04-13T00:22Z) Inspected the current Swift package and the Sunclub monorepo layout.
- [x] (2026-04-13T00:22Z) Chose Tuist for the moved macOS app, static HTML/CSS for the website, and `shorty.peyton.app` plus `shorty@peyton.app` for public metadata.
- [x] (2026-04-13T01:30Z) Moved the app into `app/Shorty/` and replaced root SwiftPM with Tuist.
- [x] (2026-04-13T01:30Z) Added root `mise`, `just`, `hk`, Python, web, docs, and CI tooling.
- [x] (2026-04-13T01:30Z) Fixed Swift 6.3 build issues discovered before and during the restructure.
- [x] (2026-04-13T01:30Z) Ran formatting, lint, tests, app build, web validation, packaging, and CI aggregate commands.

## Surprises & Discoveries

- Observation: The original root `swift test` does not compile under the installed Swift 6.3 toolchain.
  Evidence: `BrowserBridge.swift` uses `read(fd, &payload + totalRead, ...)`, which Swift cannot type-check, and `ShortcutEngine.swift` passes `kAXTrustedCheckOptionPrompt` as an unmanaged dictionary key.

- Observation: Shorty has no checked-in README or CI workflow before this change.
  Evidence: `git ls-files` only listed `.gitignore`, `Package.swift`, Swift source files, browser extension resources, and one test file.

- Observation: Tuist's generated `Shorty` scheme has no test action, while the generated `ShortyCore` scheme does run the unit tests.
  Evidence: `xcodebuild -list -workspace app/Shorty.xcworkspace` listed `Shorty`, `Shorty-Workspace`, and `ShortyCore`; `just test-app` uses `TEST_SCHEME=ShortyCore`.

- Observation: Tuist compilation cache integration timed out against the local CAS socket with the installed Xcode beta.
  Evidence: app builds failed while contacting `/Users/peyton/.local/state/tuist/peyton_shorty.sock`; disabling `COMPILATION_CACHE_ENABLE_CACHING` and `COMPILATION_CACHE_ENABLE_PLUGIN` restored deterministic local builds.

- Observation: The website package recipe must depend on `web-build` rather than running build and package work in one recipe shell.
  Evidence: `just` runs recipe lines in separate shells, so dependency ordering avoids a race where packaging can start before `.build/web` exists.

- Observation: The Tuist migration exposed additional app compile and lint issues beyond the two known SwiftPM failures.
  Evidence: fixes were needed for a malformed `SettingsView` text literal, missing `AdapterRegistry.allAdapters`, nested SwiftUI binding assignment, short identifier SwiftLint violations, and forced Accessibility casts.

## Decision Log

- Decision: Use Tuist as the app build system after moving the app into `app/`.
  Rationale: The user explicitly selected “Convert to Tuist” after reviewing the implementation tradeoff.
  Date/Author: 2026-04-13 / Codex

- Decision: Keep the website as a static site with Python validation and packaging.
  Rationale: The user selected the static site option, and it matches the Sunclub pattern without adding a heavier JavaScript framework.
  Date/Author: 2026-04-13 / Codex

- Decision: Use `https://shorty.peyton.app/` and `shorty@peyton.app` as canonical website defaults.
  Rationale: The user selected those public defaults for metadata, sitemap, robots, and support copy.
  Date/Author: 2026-04-13 / Codex

- Decision: Keep app tests on the generated `ShortyCore` scheme.
  Rationale: The generated app scheme is useful for build and run workflows, but the testable unit-test target is exposed by the framework scheme.
  Date/Author: 2026-04-13 / Codex

- Decision: Disable Tuist compilation cache for local and CI xcodebuild invocations.
  Rationale: The local CAS socket failure was environmental and unrelated to Shorty; disabling it keeps clean-checkout commands deterministic.
  Date/Author: 2026-04-13 / Codex

## Outcomes & Retrospective

Shorty now has a monorepo layout with the macOS app under `app/Shorty/`, static website under `web/`, documentation under `docs/`, automation under `scripts/`, Python checks under `tests/`, and CI under `.github/workflows/`. The root command surface is pinned through `mise`, exposed through `just`, and checked through `hk`.

Validation completed successfully:

    just bootstrap
    just fmt
    just lint
    just test-python
    just test-app
    just web-build
    just web-package VERSION=test
    just ci

`just web-package VERSION=test` produced `.build/releases/shorty-web-test.tar.gz` and `.build/releases/shorty-web-test.tar.gz.sha256`. `just test-app` ran 15 XCTest cases with 0 failures. `just test-python` ran 3 pytest tests with 0 failures. `just ci` completed the aggregate local CI path, including the Release macOS app build.

## Context and Orientation

Before this conversion, Shorty was a Swift package at the repository root. `Sources/Shorty` held the menu-bar app entry point and SwiftUI views. `Sources/ShortyCore` held app monitoring, adapter loading, shortcut matching, event tap, menu introspection, browser bridge, models, and bundled browser-extension resources. `Tests/ShortyCoreTests` held unit tests for shortcut parsing, default shortcuts, adapters, and intent matching.

A monorepo is a repository that contains multiple related projects under one root. In this repository, `app/` is the app project, `web/` is the static website, `scripts/` is shared automation, and `docs/` is written project documentation. Tuist is the Xcode project generator used from `app/`; it creates `app/Shorty.xcworkspace` from Swift manifest files.

## Plan of Work

Move the app sources into `app/Shorty/` and create Tuist manifests that define a macOS app target named `Shorty`, a framework target named `ShortyCore`, and unit tests named `ShortyCoreTests`. The app target depends on the framework target, and the framework target owns the existing browser-extension resources.

Add root automation files copied in spirit from Sunclub but simplified for Shorty: `mise.toml` pins tools, `justfile` exposes stable workflows, `hk.pkl` defines lint steps, `pyproject.toml` declares Python tooling, and `scripts/` contains thin wrappers around Tuist, xcodebuild, web validation, and packaging.

Add a static website under `web/` with `index.html`, `support/index.html`, `privacy/index.html`, `404.html`, `robots.txt`, `sitemap.xml`, `assets/site.css`, and `assets/app-icon.svg`. The site explains Shorty as a macOS menu-bar app for consistent keyboard shortcuts across apps and states the privacy behavior plainly.

Add `.github/workflows/ci.yml` with Ubuntu lint/Python/web shards and a macOS app build shard. The CI commands must call root `just` targets through `mise exec`.

Fix the two Swift 6.3 compile errors while moving code: use a stable mutable byte buffer for socket reads in `BrowserBridge`, and create a normal Core Foundation dictionary key for Accessibility permission checks in `ShortcutEngine`.

## Concrete Steps

From the repository root, create the new directory layout:

    mkdir -p app/Shorty docs scripts/tooling scripts/web tests web/assets web/privacy web/support .github/workflows

Move existing app code:

    git mv Sources app/Shorty/Sources
    git mv Tests app/Shorty/Tests

Add Tuist manifests and app plist files, then generate the workspace:

    mise exec -- tuist generate --path app --no-open

Run the root command surface:

    just bootstrap
    just generate
    just test-app
    just test-python
    just web-check
    just web-build
    just web-package VERSION=test
    just lint
    just build
    just ci

## Validation and Acceptance

`just generate` must create `app/Shorty.xcworkspace`. `just test-app` must run `ShortyCoreTests` through xcodebuild and pass. `just test-python` must run the Python validation tests and pass. `just web-check` must validate every required static site file, metadata value, and internal link. `just web-package VERSION=test` must create `.build/releases/shorty-web-test.tar.gz` and a matching `.sha256` file. `just lint` must run hk checks and SwiftLint on macOS. `just build` must build the macOS app with signing disabled for local validation. `just ci` must run the same aggregate checks expected by GitHub Actions.

## Idempotence and Recovery

The root commands are intended to be repeatable. `just generate` regenerates the Tuist workspace. `just clean-build` removes generated workspaces and build outputs. `just clean-generated` also removes local tool caches, virtual environments, and Python caches. If Tuist generation fails, run `just clean-build` and retry `just generate`.

## Artifacts and Notes

The first known failing build before changes produced these relevant errors:

    BrowserBridge.swift:169:43: error: generic parameter 'Element' could not be inferred
    ShortcutEngine.swift:125:14: error: cannot convert value of type 'Unmanaged<CFString>' to expected dictionary key type 'AnyHashable'

These errors are part of the acceptance criteria because clean-checkout commands must build with the pinned toolchain.

## Interfaces and Dependencies

Root commands are the public development interface. Do not require direct Tuist, xcodebuild, Python, or npm commands for ordinary workflows. Use `mise exec -- just <target>` in CI and document plain `just <target>` for local development after `just bootstrap`.

Pinned tools live in `mise.toml`. Python tooling uses `uv` and the root `pyproject.toml`. The app target and tests are defined by Tuist manifests under `app/`. The website is dependency-light static HTML/CSS validated by Python scripts under `scripts/web/`.
