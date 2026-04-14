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

`just run` builds the Debug app and opens the generated `.app` bundle.

## Permissions

Shorty installs a keyboard event tap, so macOS must grant Accessibility permission before remapping works. The status-bar popover surfaces the permission state and opens the relevant system prompt when permission is missing.
