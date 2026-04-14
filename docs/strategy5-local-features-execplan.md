# Strategy 5 Local Features ExecPlan

This plan implements the practical local portions of Strategy 5 from `docs/keyboard-unifier-strategies.md`. It keeps the app offline-first and avoids cloud services, account systems, or runtime dependency installation.

## Goals

- Start Shorty at app launch, not only after the menu bar popover opens.
- Generate conservative auto adapters from menu introspection when matches are high confidence.
- Add runtime diagnostics for the active app, effective adapter, adapter source, mapping count, and current web domain.
- Add a local browser bridge path from Chrome extension events to Shorty's Unix socket.
- Add built-in web adapters for known productivity domains.
- Expand tests for matching, domain normalization, browser bridge message handling, and web adapter registration.
- Update README with the monorepo layout, setup, commands, permissions, architecture, and roadmap.

## Non-Goals

- No LLM adapter generation.
- No adapter marketplace or syncing.
- No system-wide browser extension packaging.
- No automatic installation of browser extensions.
- No user tracking or external telemetry.

## Implementation Steps

1. Add a domain normalization helper shared by app monitoring and tests.
2. Update `IntentMatcher` to return scored matches with reasons and ambiguity protection.
3. Gate menu-introspection adapter creation on exact aliases, exact key combos, or high confidence scores.
4. Add built-in web adapters for Notion, Slack, Gmail, Google Docs, Figma, and Linear.
5. Instantiate `MenuIntrospector` and `BrowserBridge` by default in `ShortcutEngine`.
6. Start the engine from the menu bar scene label so it runs at application launch.
7. Add diagnostics to the menu bar popover and improve adapter detail rendering in settings.
8. Add `ShortyBridge`, a command-line native messaging proxy target.
9. Add a repo-local install script and `just` recipe for the native messaging manifest.
10. Update the browser extension background worker to forward content-script domain updates.
11. Add focused unit tests for the changed behavior.
12. Update README.
13. Verify via the standard root automation.

## Progress

- [x] Imported the Strategy 5 implementation document into `docs/`.
- [x] Added `ripgrep` to the pinned `mise` tools.
- [x] Implement local Strategy 5 runtime changes.
- [x] Add bridge install automation.
- [x] Expand tests.
- [x] Update README.
- [x] Run verification.

## Verification

Run these from the repository root:

```sh
just generate
just test-app
just build
just test-python
just web-check
just fmt
just lint
just ci
```
