# Shorty Troubleshooting

Shorty is a local menu bar app. Start with the visible state in the menu bar
popover: permission, enabled state, active app support, event tap status, and
optional browser bridge status.

## Accessibility Permission

Shorty needs macOS Accessibility access to read menu items and install its
keyboard event tap.

1. Open Shorty from Applications.
2. Choose **Open Accessibility Settings** in the Shorty popover.
3. Allow Shorty in System Settings > Privacy & Security > Accessibility.
4. Return to Shorty and choose **Check Again**.

Shorty retries the event tap after permission is granted. A quit and reopen
should not be required.

## Shorty Is Not Running

If shortcuts are not changing and the Shorty menu bar icon is missing, open the
app again from Applications. The keyboard engine starts from the app lifecycle,
not from a visible settings window.

If the icon is visible but shortcuts still pass through, confirm that Shorty is
enabled in the popover and that Accessibility permission is granted.

## Adapter Pass-Through

Shorty only remaps shortcuts for apps with trusted adapters. When the active app
has no adapter, Shorty passes the original key event through unchanged.

Use the popover to confirm:

- the active app name
- whether Shorty is enabled for it
- the current shortcut coverage count
- the next action Shorty recommends

Generated menu-introspection adapters are disabled by default for release. Use
the explicit Generate Adapter action in Settings, review the preview, then save
only adapters you trust.

## Browser Bridge

The browser bridge is optional. Native macOS app support works without it.

Install the bridge after loading the bundled browser extension as an unpacked
extension and copying its Chrome extension ID:

```sh
just install-browser-bridge EXTENSION_ID=<extension-id> BROWSERS=chrome
```

Supported browser targets are `chrome`, `chrome-canary`, `chromium`, `brave`,
`edge`, and `vivaldi`. Use a comma-separated list or `BROWSERS=all`.

To remove the native messaging manifests:

```sh
just uninstall-browser-bridge BROWSERS=all
```

If the bridge does not connect, check that:

- Shorty is running.
- The extension ID matches the native messaging manifest.
- The helper exists at
  `~/Library/Application Support/Shorty/BrowserBridge/shorty-bridge`.
- The selected browser has the manifest under its Application Support native
  messaging directory.
- The active tab is one of the supported web app domains.

By default, the extension reports only supported web app domains. All-domain
reporting is reserved for advanced diagnostics and is off in release defaults.

## Release Archive Checks

Release archives are written as `shorty-<version>-macos.zip` with a matching
`.sha256` file.

Verify a downloaded archive with:

```sh
shasum -a 256 shorty-<version>-macos.zip
```

The output should match the checksum line published with the release asset.
