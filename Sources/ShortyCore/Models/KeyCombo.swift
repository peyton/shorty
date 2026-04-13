import Carbon.HIToolbox
import CoreGraphics

/// A keyboard combination: a virtual keycode plus modifier flags.
///
/// KeyCombo is the universal currency of the shortcut engine — every canonical
/// shortcut and every adapter mapping ultimately resolves to one of these.
public struct KeyCombo: Codable, Hashable, CustomStringConvertible {
    /// macOS virtual keycode (e.g., 0x25 for "L", 0x24 for Return).
    public let keyCode: UInt16

    /// Modifier flags expressed as a stable set of named modifiers,
    /// rather than raw CGEventFlags (which contain device-specific bits).
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Parse a human-readable string like "cmd+shift+l" into a KeyCombo.
    /// Returns nil if any component is unrecognized.
    public init?(from string: String) {
        let parts = string.lowercased().split(separator: "+").map(String.init)
        var mods: Modifiers = []
        var key: String?

        for part in parts {
            switch part {
            case "cmd", "command", "⌘":
                mods.insert(.command)
            case "shift", "⇧":
                mods.insert(.shift)
            case "alt", "opt", "option", "⌥":
                mods.insert(.option)
            case "ctrl", "control", "⌃":
                mods.insert(.control)
            default:
                // Last non-modifier part is the key
                key = part
            }
        }

        guard let keyName = key, let code = KeyCodeMap.keyCode(for: keyName) else {
            return nil
        }

        self.keyCode = code
        self.modifiers = mods
    }

    // MARK: - CGEvent integration

    /// Build a KeyCombo from a live CGEvent.
    public init(event: CGEvent) {
        self.keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        self.modifiers = Modifiers(cgFlags: event.flags)
    }

    /// The CGEventFlags representation of our modifiers.
    public var cgFlags: CGEventFlags {
        modifiers.cgFlags
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("alt") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        parts.append(KeyCodeMap.keyName(for: keyCode) ?? "0x\(String(keyCode, radix: 16))")
        return parts.joined(separator: "+")
    }
}

// MARK: - Modifiers

extension KeyCombo {
    /// A portable, serializable set of modifier keys.
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        public static let command  = Modifiers(rawValue: 1 << 0)
        public static let shift    = Modifiers(rawValue: 1 << 1)
        public static let option   = Modifiers(rawValue: 1 << 2)
        public static let control  = Modifiers(rawValue: 1 << 3)

        /// Convert from CGEventFlags, stripping device-specific bits.
        public init(cgFlags: CGEventFlags) {
            var m: Modifiers = []
            if cgFlags.contains(.maskCommand)   { m.insert(.command) }
            if cgFlags.contains(.maskShift)     { m.insert(.shift) }
            if cgFlags.contains(.maskAlternate) { m.insert(.option) }
            if cgFlags.contains(.maskControl)   { m.insert(.control) }
            self = m
        }

        /// Convert back to CGEventFlags.
        public var cgFlags: CGEventFlags {
            var flags: CGEventFlags = []
            if contains(.command)  { flags.insert(.maskCommand) }
            if contains(.shift)    { flags.insert(.maskShift) }
            if contains(.option)   { flags.insert(.maskAlternate) }
            if contains(.control)  { flags.insert(.maskControl) }
            return flags
        }
    }
}
