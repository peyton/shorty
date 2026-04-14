# Contributing

Shorty is free software under the GNU Affero General Public License version 3 or
later. Contributions are accepted under the same license.

## Development Setup

Start from a clean checkout with macOS, Xcode, `mise`, and `just` installed.

```sh
just bootstrap
just generate
just build
just test
```

Use repo-local entry points instead of ad-hoc global tools. Common workflows are
documented in `README.md` and exposed through `just --list`.

## Contribution Guidelines

- Keep changes focused and reviewable.
- Prefer existing SwiftUI, Tuist, Python, and static-site patterns.
- Add or update tests when behavior changes.
- Update adjacent docs when setup, release, privacy, or licensing behavior
  changes.
- Keep new runtime dependencies lean and document their license before bundling
  them in the app.

## Legal and Attribution

Do not add source files, icons, fonts, generated assets, or libraries unless
their license is compatible with AGPL-3.0-or-later distribution. Runtime
dependencies that ship inside Shorty.app must be reflected in
`THIRD_PARTY_NOTICES.md`, the bundled legal resources, and Settings > About.

## Verification

For substantial changes, run the narrowest useful command first, then the wider
workflow before handing off:

```sh
just test-python
just web-check
just test-app
just build
```

Release-facing changes should also run the relevant packaging or verification
targets documented in `README.md`.
