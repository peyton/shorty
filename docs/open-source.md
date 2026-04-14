# Open Source Distribution

Shorty is free software licensed under the GNU Affero General Public License
version 3 or later. The SPDX license identifier is `AGPL-3.0-or-later`.

## License Intent

Shorty should remain free for users to inspect, run, modify, and redistribute.
The AGPL keeps those freedoms attached to distributed copies and to modified
network-accessible versions.

The complete license is in `LICENSE`. Shorty-specific copyright, warranty, and
source availability notes are in `NOTICE`.

## Release Artifacts

Direct-download releases are the primary public distribution path. Each public
release should include:

- `shorty-<version>-macos.zip`
- `shorty-<version>-macos.zip.sha256`
- `shorty-<version>-source.tar.gz`
- `shorty-<version>-source.tar.gz.sha256`

The source archive should come from the same git state used for the app archive.
Users should be able to verify the checksum before opening either archive.

## Attribution Policy

Shorty currently bundles no third-party runtime libraries. Apple frameworks are
provided by macOS or the Xcode SDK and are not redistributed in the app.

Before bundling any new runtime dependency, update:

- `THIRD_PARTY_NOTICES.md`
- `app/Shorty/Sources/Shorty/Resources/Legal/THIRD_PARTY_NOTICES.md`
- Settings > About
- release tests that verify legal resources

Development-only tools belong in `mise.toml`, `uv.lock`, `hk.pkl`, or adjacent
tooling docs. They should not be listed as app-bundled runtime dependencies
unless they ship inside `Shorty.app`.

## App Store Candidate

The App Store target remains a candidate build for evaluation, but the
direct-download lane is the default AGPL public release path. Any App Store
submission must receive legal review for AGPL source availability, store terms,
extension distribution, and user-facing notices before it is treated as a
supported public distribution channel.

## Release Checklist

Run the relevant release checks from a clean checkout:

```sh
just source-package VERSION=1.0.0
SHORTY_ALLOW_AD_HOC_RELEASE=1 SHORTY_CODESIGN_IDENTITY=- just app-package VERSION=1.0.0
just release-verify VERSION=1.0.0
```

Credentialed public releases should additionally use Developer ID signing,
notarization, stapling, and Sparkle signing as documented in `README.md`.
