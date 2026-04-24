import Foundation

/// HotkeyMap stores hotkeys bucketed by keycode for O(1) hash lookup,
/// then performs a linear scan within the bucket for modifier matching.
/// This reproduces Zig's ArrayHashMap with custom hash(keycode-only) + adapter equality.
public final class HotkeyMap {
    // keycode → list of hotkeys sharing that keycode (different modifiers)
    private var buckets: [UInt32: [Hotkey]] = [:]

    public init() {}

    public var count: Int { buckets.values.reduce(0) { $0 + $1.count } }

    /// Insert a hotkey. Throws if an equivalent hotkey (by flags+key) already exists.
    public func insert(_ hotkey: Hotkey) throws {
        if lookup(keyPress: KeyPress(flags: hotkey.flags, key: hotkey.key)) != nil {
            throw HotkeyError.duplicateHotkeyInMode
        }
        buckets[hotkey.key, default: []].append(hotkey)
    }

    /// Look up a hotkey using keyboard event flags (general modifier matching).
    public func lookup(keyPress: KeyPress) -> Hotkey? {
        guard let bucket = buckets[keyPress.key] else { return nil }
        return bucket.first { hotkeyFlagsMatch(config: $0.flags, keyboard: keyPress.flags) }
    }

    public func allHotkeys() -> [Hotkey] {
        buckets.values.flatMap { $0 }
    }
}
