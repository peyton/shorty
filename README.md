# Shorty

Shorty is a macOS menu-bar app for using one consistent set of keyboard shortcuts across native apps and selected web apps. It watches the frontmost app, resolves a canonical shortcut intent through an adapter, and remaps or passes through the event.

The current implementation is local-first. Adapters are bundled, user-created, or generated from macOS menu introspection and stored under Application Support. No external service is required.

## Repository Layout

- `app/` - Tuist macOS app workspace, Swift targets, tests, and bundled browser extension resources.
- `web/` - static public website.
- `docs/` - planning, architecture notes, and implementation strategy documents.
- `scripts/` - repo-local automation behind `just` targets.
- `tests/` - Python tests for repository scripts and static site checks.

Useful docs:

- [Keyboard unifier strategies](docs/keyboard-unifier-strategies.md)
- [Strategy 5 local features ExecPlan](docs/strategy5-local-features-execplan.md)
- [Release hardening ExecPlan](docs/release-hardening-execplan.md)
- [Troubleshooting](docs/troubleshooting.md)
- [App workspace notes](app/README.md)

## Requirements

- macOS with Xcode.
- `mise` and `just` available for the first bootstrap.

After bootstrap, use the repo-root `just` targets. Tool versions are pinned in `mise.toml`; Python dependencies are pinned through `uv.lock`; hooks and lint orchestration are configured through `hk`.

## Setup

```sh
just bootstrap
just generate
just build
```

Run the app:

```sh
just run
```

Shorty needs Accessibility permission before it can read app menus and install the keyboard event tap. Open the menu bar item and use Open Accessibility Settings, grant Shorty access, then choose Check Again in the popover.

## Browser Bridge

The optional browser bridge lets Shorty use web-app adapters while supported Chrome-family browsers are frontmost. Native app shortcut remapping does not require it. The bridge path has three parts:

- bundled extension resources in `app/Shorty/Sources/ShortyCore/Resources/BrowserExtension/`
- the `ShortyBridge` command-line target, which proxies Chrome Native Messaging stdin/stdout to Shorty's Unix socket
- the in-app `BrowserBridge`, which updates the current web domain

Local install flow:

1. Build and run Shorty.
2. In Chrome, load the browser extension directory as an unpacked extension.
3. Copy the extension ID.
4. Install the native messaging manifest for one or more browsers:

```sh
just install-browser-bridge EXTENSION_ID=<chrome-extension-id> BROWSERS=chrome,brave,edge
```

The install command validates the extension ID, builds `ShortyBridge`, copies it to `~/Library/Application Support/Shorty/BrowserBridge/shorty-bridge`, and writes native messaging manifests under the selected browser Application Support directories.

Supported browser targets are `chrome`, `chrome-canary`, `chromium`, `brave`, `edge`, and `vivaldi`. Use `BROWSERS=all` for every supported manifest directory.

Uninstall manifests:

```sh
just uninstall-browser-bridge BROWSERS=all
```

Supported normalized web adapter IDs:

- `web:notion.so`
- `web:slack.com`
- `web:mail.google.com`
- `web:docs.google.com`
- `web:calendar.google.com`
- `web:drive.google.com`
- `web:sheets.google.com`
- `web:slides.google.com`
- `web:meet.google.com`
- `web:figma.com`
- `web:linear.app`
- `web:chatgpt.com`
- `web:claude.ai`
- `web:github.com`
- `web:whatsapp.com`

Built-in native adapters cover common browser, code editor, terminal, document,
chat, media, and productivity shortcuts for audited apps including Safari,
Chrome-family browsers, Firefox, ChatGPT Atlas, ChatGPT, Codex, Claude, VS Code,
VS Code Insiders, Zed, Antigravity, Xcode, Terminal, iTerm2, Ghostty, Finder,
TextEdit, Notes, Mail, Messages, Preview, Calendar, Maps, Contacts, Music,
Podcasts, Slack, Discord, Signal, WhatsApp, Zoom, Notion, Notion Mail, Notion
Calendar, Obsidian, Raycast, Tot, Things, OmniFocus, GoodLinks, Craft, Zettlr,
Zotero, GitHub Desktop, HTTPie, 1Password, Figma, tldraw, Spotify, Microsoft
Office, and iWork.

## Commands

App:

- `just generate` - generate `app/Shorty.xcworkspace` with Tuist.
- `just build` - build the app.
- `just run` - build and launch the app.
- `just test-app` - run Swift tests.
- `just integration` - build a small macOS fixture app and exercise launch/menu automation.
- `just install-browser-bridge EXTENSION_ID=<id> BROWSERS=chrome` - build and install browser native messaging manifests.
- `just uninstall-browser-bridge BROWSERS=chrome` - remove browser native messaging manifests.

Release:

- `just release-preflight VERSION=1.0.0` - verify a clean public release state.
- `just app-package VERSION=1.0.0` - build, sign, zip, and checksum the app under `.build/releases/`.
- `just app-package VERSION=1.0.0 ARTIFACT_LABEL=preview-<sha>` - build a preview archive whose bundled app still reports SemVer `1.0.0`.
- `just app-notarize VERSION=1.0.0` - submit the app archive to Apple notarization, staple the app, and repackage it.
- `just dmg-package VERSION=1.0.0` - create a DMG with `Shorty.app` and an Applications shortcut.
- `just safari-extension-verify` - verify the built app contains the Safari Web Extension bundle and manifest.
- `just release-verify VERSION=1.0.0` - verify the zip, checksum, bundle version, and Safari extension contents.
- `just appcast-generate VERSION=1.0.0 DOWNLOAD_URL=<url>` - generate a Sparkle appcast from the signed zip. Requires `SHORTY_SPARKLE_ED_SIGNATURE` for release use.
- `just app-store-build VERSION=1.0.0 BUILD_NUMBER=123` - build the sandboxed App Store candidate target with TestFlight-compatible version metadata.
- `just app-store-validate VERSION=1.0.0 BUILD_NUMBER=123` - verify the App Store candidate bundle composition, sandbox entitlement, Safari extension, SemVer, and numeric Apple build number.
- `just app-store-archive VERSION=1.0.0 BUILD_NUMBER=123` - create a signed App Store `.xcarchive`. Requires explicit local signing or App Store Connect API credentials.
- `just app-store-export-testflight VERSION=1.0.0 BUILD_NUMBER=123` - upload the signed archive to App Store Connect for internal TestFlight testing. Requires App Store Connect API credentials.
- `just release VERSION=1.0.0` - run the strict Developer ID release lane: preflight, packaging, notarization, DMG, and strict verification. Use `LANE=app-store-candidate` for the secondary App Store candidate build.

Web:

- `just web-serve` - serve `web/` locally.
- `just web-check` - validate and formatting-check the static site.
- `just web-fmt` - format static site files.
- `just web-build` - copy the checked site to `.build/web/`.
- `just marketing-screenshots` - render deterministic native marketing screenshots into `web/assets/screenshots/`.
- `just web-package VERSION=test` - package the static site and checksum.

Repository:

- `just test-python` - run Python tests.
- `just test` - run app, Python, and macOS integration tests.
- `just lint` - run web checks and repository lint.
- `just fmt` - format supported repo files.
- `just ci` - run the full local CI workflow.
- `just clean` - remove generated build, cache, and environment outputs.

## Architecture

`ShortcutEngine` owns the app monitor, adapter registry, event tap, menu introspector, and browser bridge. The app starts the engine from the app lifecycle so startup remains independent of menu bar label rendering.

`AppMonitor` publishes the active native bundle ID and optional web domain. Browser domains are normalized before adapter lookup, so subdomains like `workspace.slack.com` resolve to `web:slack.com`.

`AdapterRegistry` loads built-in adapters first, then reviewed user adapters from `~/Library/Application Support/Shorty/Adapters/`. Adapter loading and saving run through validation and rebuild an indexed shortcut resolver for fast effective-app lookups.

`IntentMatcher` is intentionally conservative for auto adapters. It accepts exact aliases, exact key combos, or scores at least `0.70`, and rejects close competing matches with a margin below `0.20`.

`EventTapManager` intercepts canonical keyDown events and either remaps the event, invokes a menu item through Accessibility, performs an AX action, or passes the event through unchanged.

## Release Notes

Direct-download app archives are created under `.build/releases/` as `shorty-<version>-macos.zip` with a matching `.sha256` file. Public `just release` lanes require Developer ID signing, Apple notarization credentials, stapling, and strict verification; local `just app-package` builds can still use ad-hoc signing for development. Preview releases use non-SemVer labels such as `preview-abcdef012345` for GitHub tags and archive names while the app bundle continues to report the root `VERSION` SemVer.

The sandboxed App Store candidate keeps TestFlight metadata separate from preview labels. `CFBundleShortVersionString` must match the root `VERSION` value, and `CFBundleVersion` must be a positive numeric build number that increases for each App Store Connect upload. To use the upload lane, set `SHORTY_APP_STORE_CONNECT_KEY_PATH`, `SHORTY_APP_STORE_CONNECT_KEY_ID`, and `SHORTY_APP_STORE_CONNECT_ISSUER_ID`. To archive with already-installed local signing assets instead, set `SHORTY_APP_STORE_ALLOW_LOCAL_SIGNING=1`.

Generated menu-introspection adapters are disabled by default for public release. Users can generate, preview, and save an adapter explicitly from Settings.
