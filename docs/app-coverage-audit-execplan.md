# App Coverage Audit ExecPlan

Shorty should explicitly support more of the apps found on this Mac without
adding telemetry, remote catalogs, or runtime dependency installation. The
audit signal for this pass is local Spotlight last-used metadata plus Dock
presence. Screen Time, browser history, user documents, and private app data are
out of scope.

## Goals

- Expand built-in adapters for recent and Dock apps found locally.
- Keep broad explicit coverage useful by passing through universal macOS
  shortcuts and remapping only well-known app-specific shortcuts.
- Correct Search Everything to use Cmd+K.
- Expand web-app domain support for common browser workflows.
- Preserve the existing adapter JSON shape, validation behavior, and user
  adapter precedence.

## Non-Goals

- No cloud shortcut lookup or adapter marketplace.
- No runtime dependency installation.
- No Screen Time, browser history, document, or private data inspection.
- No adapters for apps with missing or malformed bundle metadata.

## Implementation Steps

1. Refactor built-in adapters around reusable common mapping templates.
2. Add audited native app adapters using conservative passthrough/remap choices.
3. Add supported web domains and matching built-in web adapters.
4. Update README support documentation.
5. Add Swift tests for catalog coverage, Cmd+K Search Everything, duplicate
   mapping protection, and domain normalization.
6. Run the repo-standard verification targets.

## Progress

- [x] Add ExecPlan.
- [x] Refactor and expand the built-in adapter catalog.
- [x] Expand web domain normalization.
- [x] Update documentation.
- [x] Add tests.
- [x] Run verification.

## Verification

Run these from the repository root:

```sh
just test-app
just test-python
just lint
just integration
just ci
```
