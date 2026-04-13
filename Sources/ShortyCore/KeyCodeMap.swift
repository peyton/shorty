import Foundation

/// Bidirectional mapping between macOS virtual keycodes and human-readable names.
///
/// Virtual keycodes are hardware-level identifiers defined in Carbon's
/// `Events.h` (now `HIToolbox/Events.h`). They identify physical key
/// positions, not characters — so keycode 0x25 is always "L" regardless
/// of keyboard layout or input method.
public enum KeyCodeMap {

    // MARK: - Public API

    /// Look up the virtual keycode for a human-readable key name.
    /// Accepts lowercase names like "l", "return", "space", "f1", etc.
    public static func keyCode(for name: String) -> UInt16? {
        nameToCode[name.lowercased()]
    }

    /// Look up the human-readable name for a virtual keycode.
    public static func keyName(for code: UInt16) -> String? {
        codeToName[code]
    }

    // MARK: - Mapping tables

    private static let nameToCode: [String: UInt16] = {
        var map: [String: UInt16] = [:]
        for (code, name) in codeToName {
            map[name] = code
        }
        // Add common aliases
        map["return"] = 0x24
        map["enter"] = 0x24
        map["esc"] = 0x35
        map["backspace"] = 0x33
        map["del"] = 0x75
        map["up"] = 0x7E
        map["down"] = 0x7D
        map["left"] = 0x7B
        map["right"] = 0x7C
        map["pgup"] = 0x74
        map["pgdown"] = 0x79
        return map
    }()

    /// Canonical names indexed by virtual keycode.
    /// Source: /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
    ///         /System/Library/Frameworks/Carbon.framework/Versions/A/
    ///         Frameworks/HIToolbox.framework/Headers/Events.h
    static let codeToName: [UInt16: String] = [
        // Letters (QWERTY layout)
        0x00: "a",
        0x01: "s",
        0x02: "d",
        0x03: "f",
        0x04: "h",
        0x05: "g",
        0x06: "z",
        0x07: "x",
        0x08: "c",
        0x09: "v",
        0x0B: "b",
        0x0C: "q",
        0x0D: "w",
        0x0E: "e",
        0x0F: "r",
        0x10: "y",
        0x11: "t",
        0x12: "1",
        0x13: "2",
        0x14: "3",
        0x15: "4",
        0x16: "6",
        0x17: "5",
        0x18: "=",
        0x19: "9",
        0x1A: "7",
        0x1B: "-",
        0x1C: "8",
        0x1D: "0",
        0x1E: "]",
        0x1F: "o",
        0x20: "u",
        0x21: "[",
        0x22: "i",
        0x23: "p",
        0x25: "l",
        0x26: "j",
        0x27: "'",
        0x28: "k",
        0x29: ";",
        0x2A: "\\",
        0x2B: ",",
        0x2C: "/",
        0x2D: "n",
        0x2E: "m",
        0x2F: ".",
        0x32: "`",

        // Special keys
        0x24: "return",
        0x30: "tab",
        0x31: "space",
        0x33: "delete",
        0x35: "escape",
        0x37: "command",  // left command (for flagsChanged)
        0x38: "shift",    // left shift
        0x3A: "option",   // left option
        0x3B: "control",  // left control
        0x3C: "rightshift",
        0x3D: "rightoption",
        0x3E: "rightcontrol",
        0x36: "rightcommand",

        // Arrow keys
        0x7B: "leftarrow",
        0x7C: "rightarrow",
        0x7D: "downarrow",
        0x7E: "uparrow",

        // Function keys
        0x7A: "f1",
        0x78: "f2",
        0x63: "f3",
        0x76: "f4",
        0x60: "f5",
        0x61: "f6",
        0x62: "f7",
        0x64: "f8",
        0x65: "f9",
        0x6D: "f10",
        0x67: "f11",
        0x6F: "f12",

        // Navigation
        0x73: "home",
        0x77: "end",
        0x74: "pageup",
        0x79: "pagedown",
        0x75: "forwarddelete",

        // Numpad
        0x52: "numpad0",
        0x53: "numpad1",
        0x54: "numpad2",
        0x55: "numpad3",
        0x56: "numpad4",
        0x57: "numpad5",
        0x58: "numpad6",
        0x59: "numpad7",
        0x5B: "numpad8",
        0x5C: "numpad9",
        0x41: "numpaddecimal",
        0x43: "numpadmultiply",
        0x45: "numpadplus",
        0x4B: "numpaddivide",
        0x4C: "numpadenter",
        0x4E: "numpadminus",
        0x51: "numpadequals",
    ]
}
