# Shorty App

Shorty is a macOS menu-bar app. It provides a small status-bar popover, a settings window, and a shortcut engine that translates canonical shortcuts into native per-app actions.

## Structure

- `Shorty/Sources/Shorty`
  - SwiftUI app entry point, status-bar popover, and settings views.
- `Shorty/Sources/ShortyCore`
  - app monitoring, adapter registry, shortcut matching, keyboard event tap, menu introspection, browser bridge, models, and bundled resources.
- `Shorty/Tests/ShortyCoreTests`
  - unit coverage for key parsing, default shortcuts, adapter lookup, and intent matching.
- `Shorty/Project.swift`
  - Tuist project manifest for the app, core framework, and tests.

## Build and Run

1. From the repo root, run `just bootstrap`.
2. Run `just generate`.
3. Open `app/Shorty.xcworkspace` in Xcode, or use root automation:
   - `just build`
   - `just run`
   - `just test-app`
   - `just integration`

`just run` builds the Debug app and opens the generated `.app` bundle.
`just integration` builds a tiny AppKit fixture app under `.build/fixtures/`
and launches it with a repo-local macOS automation probe. The probe verifies
app activation on every run and verifies fixture menu structure when
Accessibility UI scripting is available. Set `SHORTY_REQUIRE_UI_AUTOMATION=1`
to make menu inspection mandatory during a release pass.

## Permissions

Shorty installs a keyboard event tap and reads app menus, so macOS must grant Accessibility permission before remapping works. The status-bar popover surfaces the permission state, opens the relevant System Settings pane, and retries permission and tap installation when the user chooses Check Again.

## Release Packaging

From the repo root:

```sh
just source-package VERSION=1.0.0
just app-package VERSION=1.0.0
```

The source command writes `shorty-1.0.0-source.tar.gz` plus a checksum. The app
command builds the Release app, signs it with `SHORTY_CODESIGN_IDENTITY` when
provided or ad-hoc signing for local validation, and writes
`shorty-1.0.0-macos.zip` plus `shorty-1.0.0-macos.zip.sha256` under
`.build/releases/`.

Preview packaging keeps the bundled app version at SemVer `1.0.0` and changes
only the artifact label:

```sh
SHORTY_BUILD_NUMBER=123 just app-package VERSION=1.0.0 ARTIFACT_LABEL=preview-test
```

The sandboxed App Store target is TestFlight-compatible when the SemVer version
and numeric build number are supplied explicitly:

```sh
just app-store-build VERSION=1.0.0 BUILD_NUMBER=123
just app-store-validate VERSION=1.0.0 BUILD_NUMBER=123
```

Optional notarization uses explicit environment variables only:

```sh
NOTARYTOOL_PROFILE=<profile> just app-notarize VERSION=1.0.0
```

Shorty is licensed as `AGPL-3.0-or-later`. Legal resources are bundled from
`Shorty/Sources/Shorty/Resources/Legal/` and shown in Settings > About. The App
Store candidate target is secondary and requires legal review before public
distribution.
