import Foundation

public final class Mode {
    public let name: String
    public var command: String?
    public var capture: Bool
    public var initialized: Bool
    public let hotkeyMap: HotkeyMap

    public init(name: String, command: String? = nil, capture: Bool = false) {
        self.name = name
        self.command = command
        self.capture = capture
        self.initialized = false
        self.hotkeyMap = HotkeyMap()
    }

    public func addHotkey(_ hotkey: Hotkey) throws {
        try hotkeyMap.insert(hotkey)
    }
}
