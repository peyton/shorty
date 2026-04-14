# Shorty: Universal Keyboard Shortcut Unifier for macOS

## Five Strategies for Building the App

---

## The Problem

Every macOS app and web app invents its own keyboard shortcuts. Cmd+L focuses the URL bar in Safari but opens "Go to Line" in VS Code. Shift+Enter sends a message in Slack but inserts a newline in Google Docs. Users must memorize dozens of app-specific key maps, and there's no system-level solution to normalize them.

The goal: let the user define **one canonical set of shortcuts** (e.g., "Cmd+L always means address/URL bar", "Shift+Enter always means newline"), and have the system translate those intentions into the correct per-app key events — automatically, across native apps and web apps alike.

---

## Strategy 1: CGEventTap Interceptor + Static Adapter Registry

### Architecture: Intercept → Lookup → Rewrite → Deliver

This is the most straightforward approach. A background daemon uses macOS's `CGEventTap` API to intercept keyboard events at the Quartz event level — before they reach any application. When a key event arrives, the daemon checks which app is frontmost (via `NSWorkspace.shared.frontmostApplication.bundleIdentifier`), looks up the appropriate translation in a per-app adapter table, rewrites the event's keycode and modifier flags, and lets the modified event continue down the event pipeline.

### How it works

1. **Event interception**: A `CGEventTap` installed at `kCGHIDEventTap` or `kCGSessionEventTap` captures all keyboard events system-wide. The tap callback receives each event before the frontmost app does.

2. **App detection**: On each event, read `NSWorkspace.shared.frontmostApplication.bundleIdentifier` to determine context. Cache this — it only changes on app-switch notifications (`didActivateApplicationNotification`).

3. **Adapter lookup**: A JSON/YAML registry maps `(canonical_shortcut, bundle_id) → native_shortcut`. For example:

   ```json
   {
     "com.microsoft.VSCode": {
       "cmd+l": "cmd+shift+o",
       "shift+enter": "enter"
     },
     "com.tinyspeck.slackmacgap": {
       "shift+enter": "alt+enter"
     }
   }
   ```

4. **Event rewriting**: The CGEventTap callback modifies the `CGEvent` in-place (changing keycode, modifier flags) and returns the modified event, or returns `nil` to swallow the original and posts a new event via `CGEvent.post()`.

5. **Passthrough**: If no adapter exists for the current app, events pass through unmodified.

### Permissions required

- **Accessibility permission** (System Settings → Privacy → Accessibility)
- **Input Monitoring** (System Settings → Privacy → Input Monitoring)

### Strengths

- Low latency (~1ms overhead per keystroke)
- Pure userspace — no kernel extensions or DriverKit needed
- Works with any native app that receives key events through the standard HID pipeline
- Battle-tested pattern (Karabiner-Elements, Hammerspoon, and BetterTouchTool all use CGEventTap)

### Weaknesses

- **Static adapters**: Someone must manually create the mapping for every app
- **Web apps are invisible**: The browser is one bundle ID (`com.google.Chrome`), so you can't distinguish Gmail from Google Docs from Figma
- **Sandboxed App Store distribution is impossible**: CGEventTap with modification requires non-sandboxed execution, ruling out the Mac App Store
- **macOS updates can break taps**: Apple has tightened CGEventTap behavior across releases (the February 2026 signing race issue is one example)

### Where LLMs fit

LLMs don't play a role at runtime in this strategy. They could be used as a **build-time tool** to bulk-generate the adapter registry by scraping documentation and shortcut lists for hundreds of apps.

---

## Strategy 2: Accessibility Tree Menu Introspection + Dynamic Binding

### Architecture: Discover → Bind → Intercept → Invoke

Instead of maintaining a static mapping of keycodes, this strategy reads the actual menu structure of the frontmost application at runtime using the macOS Accessibility API. Every standard macOS app exposes its menus (and their keyboard shortcuts) via `AXUIElement`. When the user presses a canonical shortcut, the system finds the corresponding _menu action_ in the target app's accessibility tree and invokes it directly.

### How it works

1. **Menu discovery**: When an app comes to the foreground, use `AXUIElementCopyAttributeValue` to walk the app's accessibility tree starting from its `AXMenuBar`. Each `AXMenuItem` exposes attributes like `AXMenuItemCmdChar` (the key equivalent) and `AXMenuItemCmdModifiers`.

2. **Semantic mapping**: Build a mapping from _semantic actions_ (not keycodes) to menu items. For example, the canonical intent "focus URL bar" maps to the menu item titled "Open Location…" in Safari (Cmd+L) and "Go to File…" in VS Code (Cmd+P). The mapping is `intent → menu_title_regex`.

3. **Action invocation**: When the user presses a canonical shortcut, instead of rewriting the key event, the system calls `AXUIElementPerformAction(menuItem, kAXPressAction)` to directly trigger the menu item. This sidesteps the keycode entirely.

4. **Fallback to CGEventTap**: For actions that don't correspond to menu items (e.g., "Shift+Enter for newline"), fall back to Strategy 1's event rewriting.

### Permissions required

- **Accessibility permission** (mandatory for AXUIElement)
- Cannot be sandboxed

### Strengths

- **Self-discovering**: The app doesn't need a pre-built adapter for every application. It can read the menu structure at runtime and find the right action.
- **Semantic, not syntactic**: Binding to "Open Location…" is more robust than binding to Cmd+L — if the app changes its shortcut, the binding still works.
- **LLM-friendly**: An LLM can map between the user's intent ("focus URL bar") and the discovered menu title ("Open Location…") with high accuracy.

### Weaknesses

- **Only works for menu-bar actions**: Many important behaviors (newline in a text field, autocomplete selection, tab switching) are not menu items.
- **Electron/web apps expose poor accessibility trees**: Apps built on Electron (Slack, VS Code, Discord) often have incomplete or flat AX trees.
- **Performance**: Walking the AX tree on every app switch adds ~50-200ms latency. Caching mitigates this but introduces staleness.
- **36% coverage problem**: Research (Screen2AX, 2025) found only 36% of the top 99 macOS apps have high-quality accessibility metadata.

### Where LLMs fit

**Core role at runtime.** When a user defines a canonical intent like "focus URL bar," an LLM maps that natural-language intent to the most likely menu title in the current app. This is a lightweight classification task that can run locally with a small model (e.g., a fine-tuned 1-3B parameter model) in under 100ms.

---

## Strategy 3: Virtual HID Device + Kernel-Level Event Pipeline

### Architecture: Grab → Transform → Reinject via Virtual Keyboard

This strategy operates at a lower level than CGEventTap. It uses a DriverKit-based virtual HID device (like Karabiner-DriverKit-VirtualHIDDevice) to grab events from the physical keyboard, transform them in a userspace daemon, and reinject them through a virtual keyboard that macOS treats as real hardware.

### How it works

1. **Physical keyboard grab**: The system extension registers as a HID event service and grabs exclusive access to the physical keyboard's event stream, preventing events from reaching the normal input pipeline.

2. **Userspace daemon processing**: The grabbed events are sent to a userspace daemon (running as root) via a UNIX domain socket. The daemon applies the same per-app logic as Strategy 1 (frontmost app detection + adapter lookup) but has richer control over the event stream.

3. **Virtual keyboard injection**: The transformed events are sent to a DriverKit-based virtual HID device that macOS recognizes as a real keyboard. The operating system delivers these events through the normal input pipeline.

4. **Per-app awareness**: The daemon monitors `NSWorkspace` for frontmost app changes and selects the appropriate adapter.

### Permissions required

- **System Extension approval** (user must approve in System Settings → Privacy → Security)
- **DriverKit entitlement** from Apple (requires applying for a special provisioning profile)
- Root privileges for the daemon

### Strengths

- **Deepest level of control**: Can intercept and transform events before any other software sees them, including other CGEventTap-based tools.
- **Handles modifier state perfectly**: Unlike CGEventTap, which sometimes has race conditions with modifier flags, the virtual HID approach controls the entire key state machine.
- **Can synthesize complex sequences**: Multi-key sequences, held keys, and timing-sensitive input are all straightforward.

### Weaknesses

- **Massive engineering effort**: Building and maintaining a DriverKit system extension is significantly harder than a CGEventTap.
- **Apple gatekeeping**: DriverKit entitlements require a direct relationship with Apple. General developer accounts lack the necessary signing privileges.
- **macOS version fragility**: As of macOS 26.4 Beta 1, virtual HID devices created via DriverKit can no longer intercept key events from the built-in MacBook keyboard (external keyboards still work). This is a serious regression.
- **Still needs per-app adapters**: The same static mapping problem as Strategy 1.
- **User trust barrier**: Asking users to approve a system extension and grant root access is a high bar.

### Where LLMs fit

Same as Strategy 1 — LLMs serve as a build-time tool for generating adapter mappings, not a runtime component.

---

## Strategy 4: LLM-Powered Visual Agent with Screen Understanding

### Architecture: Screenshot → Understand → Act

This is the most novel and LLM-native approach. Instead of intercepting keyboard events at the system level, this strategy uses a vision-language model (VLM) to _understand what the user is looking at_ and determine the correct action to perform. When the user presses a canonical shortcut, the system takes a screenshot, identifies the active UI context (URL bar, text field, code editor, chat input), and executes the appropriate native action.

### How it works

1. **Canonical shortcut capture**: A lightweight CGEventTap captures only the user's canonical shortcuts (a small set, ~20-50 bindings). This is much simpler than intercepting all keyboard events.

2. **Screenshot capture**: On canonical shortcut press, capture a screenshot of the frontmost window using `CGWindowListCreateImage`.

3. **VLM analysis**: Send the screenshot + the user's intent to a vision-language model. The model returns a structured response: the type of UI element in focus, the action to perform, and the native shortcut or AX action to execute.

   Example prompt: _"The user pressed their 'focus URL bar' shortcut. The frontmost app is Chrome. Here's a screenshot. What native action should be performed?"_

   Example response: _"The active tab shows Gmail. There is no URL bar visible in the current viewport. The user likely wants to focus the browser's address bar. Execute Cmd+L."_

4. **Action execution**: Execute the determined action via CGEvent posting or AXUIElement invocation.

5. **Caching and learning**: Cache `(bundle_id, window_title_pattern, intent) → action` so the VLM is only called for novel contexts. Over time, the system builds its own adapter registry from experience.

### Permissions required

- Accessibility permission
- Screen Recording permission (for screenshots)
- Network access (for cloud VLM) or local model

### Strengths

- **Zero-configuration adapters**: The system figures out what to do by looking at the screen, just like a human would. No pre-built adapter registry needed.
- **Web app awareness**: Unlike all other strategies, this one can distinguish between different web apps running in the same browser, because it can see the page content.
- **Handles novel apps**: When you install a new app, the system can figure out its shortcuts by visual inspection without any adapter development.
- **Self-improving**: Each successful interaction can be cached, building a crowd-sourced adapter database over time.

### Weaknesses

- **Latency**: A cloud VLM call takes 500-2000ms. Even a local model takes 200-500ms. This is too slow for fluent typing.
- **Cost**: Cloud VLM calls with screenshots are expensive at scale (every shortcut press = one API call until cached).
- **Privacy**: Sending screenshots to a cloud API raises significant privacy concerns — screenshots may contain passwords, financial data, personal messages.
- **Reliability**: VLMs hallucinate. A 95% accuracy rate means 1 in 20 shortcut presses does the wrong thing, which is unacceptable for muscle-memory behavior.
- **Can't handle sub-application context**: The VLM can tell you're in VS Code, but determining which panel has focus (editor vs. terminal vs. sidebar) from a screenshot is unreliable.

### Where LLMs fit

**LLM is the entire runtime engine.** This strategy lives or dies on model quality. The critical insight is that it should be used as a **bootstrapping mechanism** — the VLM generates adapters that are then verified by the user and cached permanently, rather than being called on every keystroke.

---

## Strategy 5: Hybrid Adaptive System (Recommended)

### Architecture: Static Core + Dynamic Discovery + LLM Bootstrapping + Community Adapters

This strategy combines the best elements of the previous four into a layered system that is fast by default, smart when it needs to be, and improves over time.

### Layer 1: Fast Path (CGEventTap + Static Adapters)

The foundation is a high-performance CGEventTap interceptor (Strategy 1) with a curated set of adapters for the ~100 most popular macOS apps. This handles 80% of use cases with sub-millisecond latency.

### Layer 2: Menu Introspection (Accessibility API)

For apps without a static adapter, the system falls back to accessibility tree introspection (Strategy 2). When an app comes to the foreground for the first time, the system reads its menu bar and attempts to automatically generate an adapter by matching menu item titles to canonical intents.

A small local LLM (3B parameters, running on Apple Silicon Neural Engine) handles the fuzzy matching:

- Canonical intent: "focus URL bar"
- Discovered menu items: ["Open Location…", "Go to URL…", "Navigate to Address…"]
- LLM output: "Open Location…" (confidence: 0.97)

This auto-generated adapter is cached and used on the fast path from then on.

### Layer 3: Browser Extension Bridge (for Web Apps)

A companion Chrome/Safari/Firefox extension solves the "one bundle ID" problem for web apps. The extension:

1. Reports the current page's domain and detected web app type (Gmail, Notion, Figma, etc.) to the native app via Native Messaging.
2. Intercepts keyboard events at the DOM level for web-app-specific shortcuts that can't be handled at the system level.
3. Applies web-app-specific adapters pushed down from the native app.

The extension communicates with the native daemon via Chrome's Native Messaging API (or Safari's App Extension equivalent), creating a bidirectional channel:

- Native → Extension: "Apply this adapter for notion.so"
- Extension → Native: "Current context: notion.so, focus is in a text block"

### Layer 4: LLM Adapter Generator (Bootstrapping)

When no adapter exists (static, auto-generated, or community), and the user presses a canonical shortcut in an unknown app, the system:

1. Takes a screenshot of the current window
2. Reads the app's accessibility tree (if available)
3. Reads the app's menu structure (if available)
4. Sends all context to a VLM with the prompt: "Generate a keyboard adapter for this application"
5. Presents the generated adapter to the user for review and confirmation
6. Caches the confirmed adapter locally

This is an **async, user-supervised process** — not a real-time per-keystroke call. The user's immediate shortcut press falls through to "no adapter" (beep or notification), and the system generates the adapter in the background for next time.

### Layer 5: Community Adapter Repository

Confirmed adapters can be shared to a community repository (think Karabiner's complex modifications gallery, but for semantic shortcut adapters). The repository is:

- Keyed by `(bundle_id, app_version_range)`
- Includes both native app and web app adapters
- Rated and verified by users
- Automatically suggested when a user encounters an app without an adapter

### Data model

```text
CanonicalShortcut:
  id: "focus_url_bar"
  default_keys: "cmd+l"
  category: "navigation"
  description: "Focus the URL/address/location bar"

Adapter:
  app_identifier: "com.microsoft.VSCode"  # or "web:notion.so"
  version_range: ">=1.85"
  mappings:
    - canonical: "focus_url_bar"
      method: "key_remap"           # or "ax_action" or "menu_invoke"
      native_keys: "cmd+p"
    - canonical: "newline_in_field"
      method: "key_remap"
      native_keys: "enter"          # plain enter does newline in VS Code
      context: "editor"             # only when editor panel is focused
```

### Strengths

- **Fast by default**: The common case (popular apps with static adapters) runs at CGEventTap speed.
- **Graceful degradation**: Unknown apps get progressively better handling — menu introspection → LLM generation → community adapters.
- **Web app support**: The browser extension layer solves the critical blind spot.
- **Self-improving**: Every user interaction potentially generates a new adapter that benefits all users.
- **LLMs used appropriately**: Not in the hot path (per-keystroke), but in the cold path (adapter generation and intent matching).

### Weaknesses

- **Significant engineering surface area**: Five distinct subsystems to build and maintain.
- **Browser extension fragility**: Each browser has different extension APIs and limitations. Safari extensions are particularly restrictive.
- **User onboarding complexity**: Accessibility permission + Input Monitoring + browser extension installation is a lot of setup.
- **The "last 20%" problem**: Some apps have genuinely unique interaction patterns that can't be mapped to a canonical set (e.g., vim-style modal editing, game controls).

---

## Comparative Summary

| Dimension              | Strategy 1      | Strategy 2      | Strategy 3              | Strategy 4       | Strategy 5          |
| ---------------------- | --------------- | --------------- | ----------------------- | ---------------- | ------------------- |
| **Latency**            | ~1ms            | ~50-200ms       | ~1ms                    | 200-2000ms       | ~1ms (fast path)    |
| **App coverage**       | Manual only     | Menu-bar apps   | Manual only             | Any visual app   | Progressive         |
| **Web app support**    | No              | No              | No                      | Yes (via vision) | Yes (via extension) |
| **Setup complexity**   | Low             | Low             | Very High               | Medium           | Medium-High         |
| **LLM dependency**     | Build-time only | Runtime (light) | Build-time only         | Runtime (heavy)  | Cold path only      |
| **Distribution**       | Direct/Homebrew | Direct/Homebrew | Direct (Apple approval) | Direct/Homebrew  | Direct/Homebrew     |
| **Engineering effort** | Medium          | Medium          | Very High               | High             | High                |
| **Privacy risk**       | Low             | Low             | Low                     | High             | Low-Medium          |

---

## Key Technical Constraints (macOS Security Model)

1. **No Mac App Store**: Any strategy using CGEventTap modification or AXUIElement on other apps requires non-sandboxed execution, which disqualifies Mac App Store distribution.

2. **Accessibility permission is mandatory**: All strategies except pure DriverKit require the user to grant Accessibility access in System Settings.

3. **Code signing matters**: As of 2026, unsigned or ad-hoc signed apps can have their CGEventTaps silently disabled. Proper Developer ID signing is essential.

4. **DriverKit is Apple-gated**: Strategy 3 requires special entitlements that Apple grants selectively.

5. **Screen recording permission**: Strategy 4 requires this, which triggers a prominent system dialog.

6. **Electron apps are a gray area**: Many popular apps (Slack, Discord, VS Code, Notion desktop) use Electron, which provides inconsistent accessibility tree quality and handles some shortcuts at the Chromium level rather than the NSMenu level.

---

## Recommended Starting Point

Build **Strategy 5 in phases**:

1. **Phase 1** (MVP): Strategy 1 core — CGEventTap + static adapters for the top 20 apps. Ship this.
2. **Phase 2**: Add Layer 2 (menu introspection with local LLM matching). This dramatically increases coverage.
3. **Phase 3**: Add the browser extension bridge. This unlocks web apps.
4. **Phase 4**: Add LLM adapter generation for unknown apps.
5. **Phase 5**: Launch the community adapter repository.

Each phase delivers standalone value while building toward the full vision.
