# Third-Party Notices

Shorty has no third-party runtime libraries bundled in the macOS app at this
time.

The app links against Apple system frameworks provided by macOS, including
AppKit, SwiftUI, Combine, Foundation, Carbon, ApplicationServices, and
SafariServices. Those frameworks are supplied by Apple as part of the operating
system or Xcode SDK and are not redistributed by this repository.

Repository development and validation use tools such as Tuist, SwiftLint, uv,
pytest, ruff, hk, mise, Prettier, shellcheck, shfmt, actionlint, zizmor, rumdl,
and pkl. These tools are not bundled into Shorty.app. Their versions are pinned
or orchestrated through `mise.toml`, `uv.lock`, `hk.pkl`, and the repo-local
`just` targets.

If a future release bundles a third-party runtime dependency, update this file,
the bundled app copy under `app/Shorty/Sources/Shorty/Resources/Legal/`, and
Settings > About before publishing the release.
