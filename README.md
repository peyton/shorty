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

Shorty needs Accessibility permission before it can install the keyboard event tap. Open the menu bar item and use the Accessibility button, or grant the built app permission in System Settings > Privacy & Security > Accessibility.

## Browser Bridge

The optional Chrome bridge lets Shorty use web-app adapters while Chrome-family browsers are frontmost. The bridge path has three parts:

- bundled extension resources in `app/Shorty/Sources/ShortyCore/Resources/BrowserExtension/`
- the `ShortyBridge` command-line target, which proxies Chrome Native Messaging stdin/stdout to Shorty's Unix socket
- the in-app `BrowserBridge`, which updates the current web domain

Local install flow:

1. Build and run Shorty.
2. In Chrome, load the browser extension directory as an unpacked extension.
3. Copy the extension ID.
4. Install the native messaging manifest:

```sh
just install-browser-bridge EXTENSION_ID=<chrome-extension-id>
```

The install command builds `ShortyBridge`, copies it to `.build/browser-bridge/shorty-bridge`, and writes Chrome's native messaging manifest under `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/`.

Supported normalized web adapter IDs:

- `web:notion.so`
- `web:slack.com`
- `web:mail.google.com`
- `web:docs.google.com`
- `web:figma.com`
- `web:linear.app`

## Commands

App:

- `just generate` - generate `app/Shorty.xcworkspace` with Tuist.
- `just build` - build the app.
- `just run` - build and launch the app.
- `just test-app` - run Swift tests.
- `just install-browser-bridge EXTENSION_ID=<id>` - build and install the Chrome native messaging host manifest.

Web:

- `just web-serve` - serve `web/` locally.
- `just web-check` - validate and formatting-check the static site.
- `just web-fmt` - format static site files.
- `just web-build` - copy the checked site to `.build/web/`.
- `just web-package VERSION=test` - package the static site and checksum.

Repository:

- `just test-python` - run Python tests.
- `just test` - run app and Python tests.
- `just lint` - run web checks and repository lint.
- `just fmt` - format supported repo files.
- `just ci` - run the full local CI workflow.
- `just clean` - remove generated build, cache, and environment outputs.

## Architecture

`ShortcutEngine` owns the app monitor, adapter registry, event tap, menu introspector, and browser bridge. The app starts the engine when the menu bar item is created.

`AppMonitor` publishes the active native bundle ID and optional web domain. Browser domains are normalized before adapter lookup, so subdomains like `workspace.slack.com` resolve to `web:slack.com`.

`AdapterRegistry` loads built-in adapters first, then auto-generated menu-introspection adapters from `~/Library/Application Support/Shorty/AutoAdapters/`, then user adapters from `~/Library/Application Support/Shorty/Adapters/`.

`IntentMatcher` is intentionally conservative for auto adapters. It accepts exact aliases, exact key combos, or scores at least `0.70`, and rejects close competing matches with a margin below `0.20`.

`EventTapManager` intercepts canonical keyDown events and either remaps the event, invokes a menu item through Accessibility, performs an AX action, or passes the event through unchanged.

## Roadmap

- Package the browser extension for easier local installation.
- Add adapter editing and export/import from Settings.
- Broaden menu-introspection coverage with richer context checks.
- Add more web-app adapters after validating shortcuts against the live apps.
- Keep cloud, marketplace, and LLM-generated adapters out of the default local flow until they have a clear trust and review model.
