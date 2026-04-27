import Carbon.HIToolbox

// MARK: - Literal keycode tables (mirrors Keycodes.zig)

public let literalKeycodeStr: [String] = [
    "return", "tab", "space",
    "backspace", "escape", "backtick",

    // Fn modifier range (index 6 through 34, inclusive)
    "delete", "home", "end",
    "pageup", "pagedown", "insert",
    "left", "right", "up",
    "down", "f1", "f2",
    "f3", "f4", "f5",
    "f6", "f7", "f8",
    "f9", "f10", "f11",
    "f12", "f13", "f14",
    "f15", "f16", "f17",
    "f18", "f19", "f20",

    // NX modifier range (index 35 onward)
    "sound_up", "sound_down", "mute",
    "play", "previous", "next",
    "rewind", "fast", "brightness_up",
    "brightness_down", "illumination_up", "illumination_down",
]

// Indices matching Keycodes.zig constants
public let keyHasImplicitFnMod = 4   // keys with index > 4 and <= keyFnModEnd get .fn_ flag
public let keyFnModEnd = 27          // F12 is the last key with implicit fn_ (F13+ are pure function keys)
public let keyHasImplicitNxMod = 35  // keys with index >= 35 get .nx flag

// Keycodes for F13-F19: macOS may or may not set maskSecondaryFn for these keys
// depending on keyboard hardware; strip fn_ from events for these to ensure consistent matching.
public let pureFunctionKeycodes: Set<UInt32> = Set(
    literalKeycodeValue[(keyFnModEnd + 1) ..< keyHasImplicitNxMod]
)

// NX key type constants (from IOKit/hidsystem/ev_keymap.h)
private let NX_KEYTYPE_SOUND_UP:          UInt32 = 0
private let NX_KEYTYPE_SOUND_DOWN:        UInt32 = 1
private let NX_KEYTYPE_MUTE:              UInt32 = 7
private let NX_KEYTYPE_PLAY:              UInt32 = 16
private let NX_KEYTYPE_NEXT:              UInt32 = 17
private let NX_KEYTYPE_PREVIOUS:          UInt32 = 18
private let NX_KEYTYPE_FAST:              UInt32 = 19
private let NX_KEYTYPE_REWIND:            UInt32 = 20
private let NX_KEYTYPE_BRIGHTNESS_UP:     UInt32 = 2
private let NX_KEYTYPE_BRIGHTNESS_DOWN:   UInt32 = 3
private let NX_KEYTYPE_ILLUMINATION_UP:   UInt32 = 21
private let NX_KEYTYPE_ILLUMINATION_DOWN: UInt32 = 22

public let literalKeycodeValue: [UInt32] = [
    UInt32(kVK_Return),      UInt32(kVK_Tab),         UInt32(kVK_Space),
    UInt32(kVK_Delete),      UInt32(kVK_Escape),       UInt32(kVK_ANSI_Grave),

    // Fn mod
    UInt32(kVK_ForwardDelete), UInt32(kVK_Home),       UInt32(kVK_End),
    UInt32(kVK_PageUp),      UInt32(kVK_PageDown),     UInt32(kVK_Help),
    UInt32(kVK_LeftArrow),   UInt32(kVK_RightArrow),   UInt32(kVK_UpArrow),
    UInt32(kVK_DownArrow),   UInt32(kVK_F1),           UInt32(kVK_F2),
    UInt32(kVK_F3),          UInt32(kVK_F4),           UInt32(kVK_F5),
    UInt32(kVK_F6),          UInt32(kVK_F7),           UInt32(kVK_F8),
    UInt32(kVK_F9),          UInt32(kVK_F10),          UInt32(kVK_F11),
    UInt32(kVK_F12),         UInt32(kVK_F13),          UInt32(kVK_F14),
    UInt32(kVK_F15),         UInt32(kVK_F16),          UInt32(kVK_F17),
    UInt32(kVK_F18),         UInt32(kVK_F19),          UInt32(kVK_F20),

    // NX mod
    NX_KEYTYPE_SOUND_UP,     NX_KEYTYPE_SOUND_DOWN,    NX_KEYTYPE_MUTE,
    NX_KEYTYPE_PLAY,         NX_KEYTYPE_PREVIOUS,      NX_KEYTYPE_NEXT,
    NX_KEYTYPE_REWIND,       NX_KEYTYPE_FAST,          NX_KEYTYPE_BRIGHTNESS_UP,
    NX_KEYTYPE_BRIGHTNESS_DOWN, NX_KEYTYPE_ILLUMINATION_UP, NX_KEYTYPE_ILLUMINATION_DOWN,
]

// MARK: - Keycodes

/// Resolves character strings to virtual key codes using the current keyboard layout.
public final class Keycodes {
    private var keymapTable: [String: UInt32] = [:]

    // Layout-dependent ANSI keycodes to scan
    private static let layoutDependentKeycodes: [Int] = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
        kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
        kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z,
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        kVK_ANSI_Grave, kVK_ANSI_Equal, kVK_ANSI_Minus,
        kVK_ANSI_RightBracket, kVK_ANSI_LeftBracket, kVK_ANSI_Quote,
        kVK_ANSI_Semicolon, kVK_ANSI_Backslash, kVK_ANSI_Comma,
        kVK_ANSI_Slash, kVK_ANSI_Period,
    ]

    public init() throws {
        guard let keyboard = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else {
            throw KeycodesError.failedToGetKeyboardLayout
        }
        guard let uchrDataPtr = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData) else {
            throw KeycodesError.failedToGetKeyboardLayout
        }
        let uchrData = Unmanaged<CFData>.fromOpaque(uchrDataPtr).takeUnretainedValue()
        guard let layoutBytes = CFDataGetBytePtr(uchrData) else {
            throw KeycodesError.failedToGetKeyboardLayout
        }

        let layoutPtr = UnsafeRawPointer(layoutBytes).bindMemory(to: UCKeyboardLayout.self, capacity: 1)
        var deadKeyState: UInt32 = 0
        var unicodeChars = [UniChar](repeating: 0, count: 255)
        var charCount: Int = 0

        for keycode in Self.layoutDependentKeycodes {
            deadKeyState = 0
            charCount = 0
            unicodeChars = [UniChar](repeating: 0, count: 255)

            let err = UCKeyTranslate(
                layoutPtr,
                UInt16(keycode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                255,
                &charCount,
                &unicodeChars
            )
            guard err == noErr, charCount > 0 else { continue }

            let str = String(utf16CodeUnits: Array(unicodeChars[0..<charCount]), count: charCount)
            if keymapTable[str] == nil {
                keymapTable[str] = UInt32(keycode)
            }
        }
    }

    public func getKeycode(_ key: String) throws -> UInt32 {
        guard let code = keymapTable[key] else {
            throw KeycodesError.keyNotFound(key)
        }
        return code
    }

    public func isLayoutKey(_ key: String) -> Bool {
        keymapTable[key] != nil
    }
}

public enum KeycodesError: Error {
    case failedToGetKeyboardLayout
    case keyNotFound(String)
}

// MARK: - Key formatting helper

public func formatKeyPress(flags: ModifierFlag, key: UInt32) -> String {
    var parts: [String] = []
    let desc = flags.description
    if !desc.isEmpty { parts.append(desc) }
    // Try to find key name
    for (i, val) in literalKeycodeValue.enumerated() {
        if val == key {
            parts.append(literalKeycodeStr[i])
            return parts.joined(separator: " - ")
        }
    }
    parts.append("0x\(String(key, radix: 16))")
    return parts.joined(separator: " - ")
}
