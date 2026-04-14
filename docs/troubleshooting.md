# Shorty Troubleshooting

## Accessibility Access Is Stuck

If Shorty still reports that Accessibility access is missing after you approve it:

1. Quit and reopen Shorty.
2. Open System Settings > Privacy & Security > Accessibility.
3. Turn Shorty off, then on again.
4. If Shorty was moved after approval, remove the old entry and add the copy in Applications.

Shorty passes shortcuts through unchanged while Accessibility access is missing.

## Browser Bridge Is Not Installed

The Chrome-family bridge is optional. Native app shortcuts still work without it.

From a checkout, install the native messaging manifest with:

```sh
just install-browser-bridge EXTENSION_ID=<32-letter-extension-id> BROWSERS=chrome,brave,edge
```

Remove manifests with:

```sh
just uninstall-browser-bridge BROWSERS=chrome,brave,edge
```

The app reports manifest status in Settings > Advanced > Browsers.

## Generated Adapters Need Review

Generated adapters are based on the active app's menus. Save them only after checking warnings for:

- Return, Shift-Return, Space, and close-window shortcuts.
- Low coverage.
- Menu titles that may change between app versions.

Generated adapters can be disabled or deleted from Settings > Apps.
