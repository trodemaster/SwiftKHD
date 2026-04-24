import Foundation

// MARK: - ModifierFlag

public struct ModifierFlag: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let alt        = ModifierFlag(rawValue: 1 << 0)
    public static let lalt       = ModifierFlag(rawValue: 1 << 1)
    public static let ralt       = ModifierFlag(rawValue: 1 << 2)
    public static let shift      = ModifierFlag(rawValue: 1 << 3)
    public static let lshift     = ModifierFlag(rawValue: 1 << 4)
    public static let rshift     = ModifierFlag(rawValue: 1 << 5)
    public static let cmd        = ModifierFlag(rawValue: 1 << 6)
    public static let lcmd       = ModifierFlag(rawValue: 1 << 7)
    public static let rcmd       = ModifierFlag(rawValue: 1 << 8)
    public static let control    = ModifierFlag(rawValue: 1 << 9)
    public static let lcontrol   = ModifierFlag(rawValue: 1 << 10)
    public static let rcontrol   = ModifierFlag(rawValue: 1 << 11)
    public static let fn_        = ModifierFlag(rawValue: 1 << 12)
    public static let passthrough = ModifierFlag(rawValue: 1 << 13)
    public static let nx         = ModifierFlag(rawValue: 1 << 14)

    public static let hyper: ModifierFlag = [.cmd, .alt, .shift, .control]
    public static let meh: ModifierFlag   = [.control, .shift, .alt]

    // Named modifier lookup table (mirrors Keycodes.zig modifier_flags_map)
    public static let namedFlags: [String: ModifierFlag] = [
        "alt":    .alt,
        "lalt":   .lalt,
        "ralt":   .ralt,
        "shift":  .shift,
        "lshift": .lshift,
        "rshift": .rshift,
        "cmd":    .cmd,
        "lcmd":   .lcmd,
        "rcmd":   .rcmd,
        "ctrl":   .control,
        "lctrl":  .lcontrol,
        "rctrl":  .rcontrol,
        "fn":     .fn_,
        "hyper":  .hyper,
        "meh":    .meh,
    ]

    public static func named(_ name: String) -> ModifierFlag? {
        namedFlags[name]
    }

    var description: String {
        var parts: [String] = []
        if contains(.alt)        { parts.append("alt") }
        if contains(.lalt)       { parts.append("lalt") }
        if contains(.ralt)       { parts.append("ralt") }
        if contains(.shift)      { parts.append("shift") }
        if contains(.lshift)     { parts.append("lshift") }
        if contains(.rshift)     { parts.append("rshift") }
        if contains(.cmd)        { parts.append("cmd") }
        if contains(.lcmd)       { parts.append("lcmd") }
        if contains(.rcmd)       { parts.append("rcmd") }
        if contains(.control)    { parts.append("ctrl") }
        if contains(.lcontrol)   { parts.append("lctrl") }
        if contains(.rcontrol)   { parts.append("rctrl") }
        if contains(.fn_)        { parts.append("fn") }
        if contains(.passthrough){ parts.append("passthrough") }
        if contains(.nx)         { parts.append("nx") }
        return parts.joined(separator: "+")
    }
}

// MARK: - hotkeyFlagsMatch

/// Exact port of Zig hotkeyFlagsMatch logic.
/// config = hotkey from config file, keyboard = event from keyboard.
/// General modifier in config (e.g. .alt) matches keyboard .alt OR .lalt OR .ralt.
/// Specific modifier in config (e.g. .lalt) requires exact match.
public func hotkeyFlagsMatch(config: ModifierFlag, keyboard: ModifierFlag) -> Bool {
    let altMatch: Bool
    if config.contains(.alt) {
        altMatch = keyboard.contains(.alt) || keyboard.contains(.lalt) || keyboard.contains(.ralt)
    } else {
        altMatch = config.contains(.lalt) == keyboard.contains(.lalt)
            && config.contains(.ralt) == keyboard.contains(.ralt)
            && config.contains(.alt) == keyboard.contains(.alt)
    }

    let cmdMatch: Bool
    if config.contains(.cmd) {
        cmdMatch = keyboard.contains(.cmd) || keyboard.contains(.lcmd) || keyboard.contains(.rcmd)
    } else {
        cmdMatch = config.contains(.lcmd) == keyboard.contains(.lcmd)
            && config.contains(.rcmd) == keyboard.contains(.rcmd)
            && config.contains(.cmd) == keyboard.contains(.cmd)
    }

    let ctrlMatch: Bool
    if config.contains(.control) {
        ctrlMatch = keyboard.contains(.control) || keyboard.contains(.lcontrol) || keyboard.contains(.rcontrol)
    } else {
        ctrlMatch = config.contains(.lcontrol) == keyboard.contains(.lcontrol)
            && config.contains(.rcontrol) == keyboard.contains(.rcontrol)
            && config.contains(.control) == keyboard.contains(.control)
    }

    let shiftMatch: Bool
    if config.contains(.shift) {
        shiftMatch = keyboard.contains(.shift) || keyboard.contains(.lshift) || keyboard.contains(.rshift)
    } else {
        shiftMatch = config.contains(.lshift) == keyboard.contains(.lshift)
            && config.contains(.rshift) == keyboard.contains(.rshift)
            && config.contains(.shift) == keyboard.contains(.shift)
    }

    return altMatch && cmdMatch && ctrlMatch && shiftMatch
        && config.contains(.fn_) == keyboard.contains(.fn_)
        && config.contains(.nx) == keyboard.contains(.nx)
}

// MARK: - KeyPress

public struct KeyPress: Hashable, Sendable {
    public var flags: ModifierFlag
    public var key: UInt32

    public init(flags: ModifierFlag = [], key: UInt32) {
        self.flags = flags
        self.key = key
    }
}

// MARK: - ProcessCommand

public enum ProcessCommand: Sendable {
    case command(String)
    case forwarded(KeyPress)
    case unbound
    case activation(modeName: String, command: String?)
}

// MARK: - Hotkey

public final class Hotkey: Sendable {
    public var flags: ModifierFlag
    public var key: UInt32
    // process name (lowercased) -> action; "*" is the wildcard
    public var mappings: [(processName: String, action: ProcessCommand)]

    public init(flags: ModifierFlag = [], key: UInt32 = 0) {
        self.flags = flags
        self.key = key
        self.mappings = []
    }

    // MARK: Adding process bindings

    public func addProcessCommand(_ processName: String, command: String) throws {
        if processName == "*" {
            if wildcardAction() != nil { throw HotkeyError.wildcardCommandAlreadyExists }
        } else if let existing = findExact(processName) {
            if case .command(let c) = existing, c == command { return } // idempotent
            throw HotkeyError.processCommandAlreadyExists
        }
        mappings.append((processName.lowercased(), .command(command)))
    }

    public func addProcessForward(_ processName: String, keyPress: KeyPress) throws {
        if processName == "*" {
            if wildcardAction() != nil { throw HotkeyError.wildcardCommandAlreadyExists }
        } else if let existing = findExact(processName) {
            if case .forwarded(let kp) = existing, kp == keyPress { return } // idempotent
            throw HotkeyError.processCommandAlreadyExists
        }
        mappings.append((processName.lowercased(), .forwarded(keyPress)))
    }

    public func addProcessUnbound(_ processName: String) throws {
        if processName == "*" {
            if wildcardAction() != nil { throw HotkeyError.wildcardCommandAlreadyExists }
        } else if let existing = findExact(processName) {
            if case .unbound = existing { return } // idempotent
            throw HotkeyError.processCommandAlreadyExists
        }
        mappings.append((processName.lowercased(), .unbound))
    }

    public func addProcessActivation(_ processName: String, modeName: String, command: String?) throws {
        if processName == "*" {
            if wildcardAction() != nil { throw HotkeyError.wildcardCommandAlreadyExists }
        } else if findExact(processName) != nil {
            throw HotkeyError.processCommandAlreadyExists
        }
        mappings.append((processName.lowercased(), .activation(modeName: modeName, command: command)))
    }

    // MARK: Lookup

    /// Find the command for a given process name (lowercased).
    /// Checks specific process name first, then wildcard "*".
    public func findCommandForProcess(_ processName: String) -> ProcessCommand? {
        let lower = processName.lowercased()
        for (name, action) in mappings where name != "*" {
            if name.lowercased() == lower { return action }
        }
        return wildcardAction()
    }

    // MARK: Private helpers

    private func findExact(_ processName: String) -> ProcessCommand? {
        let lower = processName.lowercased()
        for (name, action) in mappings where name != "*" {
            if name == lower { return action }
        }
        return nil
    }

    private func wildcardAction() -> ProcessCommand? {
        for (name, action) in mappings where name == "*" { return action }
        return nil
    }
}

// MARK: - Errors

public enum HotkeyError: Error {
    case processCommandAlreadyExists
    case wildcardCommandAlreadyExists
    case duplicateHotkeyInMode
}
