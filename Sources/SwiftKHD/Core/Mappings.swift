import Foundation

public final class Mappings {
    public var modeMap: [String: Mode] = [:]
    public var blacklist: Set<String> = []
    public var shell: String
    public var loadedFiles: [String] = []

    public init() {
        self.shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/bash"
        // Always create the default mode
        modeMap["default"] = Mode(name: "default")
    }

    // MARK: Mode management

    public func getOrCreateMode(_ name: String) -> Mode? {
        if let existing = modeMap[name] { return existing }
        // Modes must be declared before use (return nil for undeclared)
        return nil
    }

    public func getOrCreateDefault(_ name: String) -> Mode? {
        if let existing = modeMap[name] { return existing }
        if name == "default" {
            let m = Mode(name: "default")
            modeMap["default"] = m
            return m
        }
        return nil
    }

    public func putMode(_ mode: Mode) {
        modeMap[mode.name] = mode
    }

    // MARK: Hotkey management

    public func addHotkey(_ hotkey: Hotkey, toModes modeNames: [String]) throws {
        for name in modeNames {
            guard let mode = modeMap[name] else { continue }
            try mode.addHotkey(hotkey)
        }
    }

    // MARK: Blacklist

    public func addBlacklist(_ appName: String) {
        blacklist.insert(appName.lowercased())
    }

    public func isBlacklisted(_ processName: String) -> Bool {
        blacklist.contains(processName.lowercased())
    }

    // MARK: Shell

    public func setShell(_ path: String) {
        shell = path
    }
}
