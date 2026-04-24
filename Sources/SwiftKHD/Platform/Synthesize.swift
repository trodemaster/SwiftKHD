import CoreGraphics
import AppKit
import Carbon.HIToolbox

// MARK: - Key synthesis

/// Synthesize a keypress from a spec like "cmd - a" or "return".
public func synthesizeKey(_ spec: String) throws {
    let keycodes = try Keycodes()
    let parser = Parser(keycodes: keycodes)
    let mappings = Mappings()
    let hotkey = Hotkey()
    // Parse the spec as a single keypress
    let content = "cmd - a : __noop\n".replacingOccurrences(of: "cmd - a", with: spec)
    _ = try? parser.parse(mappings: mappings, content: content + " : __noop")

    // Simpler: parse manually
    var tok = Tokenizer(buffer: spec.trimmingCharacters(in: .whitespaces))
    var flags: ModifierFlag = []
    var key: UInt32?

    func nextTok() -> Token? { tok.nextToken() }

    var token = nextTok()
    while let t = token {
        switch t.type {
        case .modifier:
            if let f = ModifierFlag.named(t.text) {
                flags = ModifierFlag(rawValue: flags.rawValue | f.rawValue)
            }
        case .key:
            key = try keycodes.getKeycode(t.text)
        case .keyHex:
            key = UInt32(t.text, radix: 16)
        case .literal:
            for (i, lit) in literalKeycodeStr.enumerated() {
                if lit == t.text { key = literalKeycodeValue[i] }
            }
        default: break
        }
        token = nextTok()
    }

    guard let keycode = key else {
        throw SynthesizeError.invalidKeySpec(spec)
    }
    _ = hotkey

    let cgFlags = modifierFlagToCGEventFlags(flags)
    let src = CGEventSource(stateID: .combinedSessionState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: true)
    let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(keycode), keyDown: false)
    down?.flags = cgFlags
    up?.flags   = cgFlags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
}

/// Synthesize text input by posting individual character events.
public func synthesizeText(_ text: String) {
    let src = CGEventSource(stateID: .combinedSessionState)
    for scalar in text.unicodeScalars {
        var chars = [UniChar(scalar.value & 0xFFFF)]
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
        down?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
        up?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &chars)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

// MARK: - Media key synthesis

/// Post a media key event (NX system key).
public func postMediaKeyEvent(keyCode: UInt32, keyDown: Bool) {
    let stateFlags: Int = keyDown ? 0x0a00 : 0x0b00
    let data1 = (Int(keyCode) << 16) | stateFlags
    guard let event = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data1,
        data2: -1
    ) else { return }
    event.cgEvent.map { $0.post(tap: .cghidEventTap) }
}

// MARK: - ModifierFlag → CGEventFlags

public func modifierFlagToCGEventFlags(_ flags: ModifierFlag) -> CGEventFlags {
    var result = CGEventFlags()
    if flags.contains(.alt) || flags.contains(.lalt) || flags.contains(.ralt) {
        result.insert(.maskAlternate)
    }
    if flags.contains(.shift) || flags.contains(.lshift) || flags.contains(.rshift) {
        result.insert(.maskShift)
    }
    if flags.contains(.cmd) || flags.contains(.lcmd) || flags.contains(.rcmd) {
        result.insert(.maskCommand)
    }
    if flags.contains(.control) || flags.contains(.lcontrol) || flags.contains(.rcontrol) {
        result.insert(.maskControl)
    }
    if flags.contains(.fn_) { result.insert(.maskSecondaryFn) }
    return result
}

public enum SynthesizeError: Error {
    case invalidKeySpec(String)
}
