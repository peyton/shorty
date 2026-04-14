# Shorty Agent Notes

- For changes to menu bar status, active-app detection, or shortcut availability, update both `ShortyCoreTests` and the SwiftUI popover tests under `app/Shorty/Tests/ShortyTests`.
- Run `just test-app` after Swift app changes; it exercises core behavior plus popover rendering.
