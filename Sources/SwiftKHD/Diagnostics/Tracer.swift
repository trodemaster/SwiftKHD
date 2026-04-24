import Foundation

/// Performance tracer for profiling event handling.
/// Enabled at runtime via --profile flag. Mirrors Tracer.zig.
public final class Tracer {
    public var enabled: Bool
    private var totalKeyEvents: Int = 0
    private var keyDownEvents: Int = 0
    private var systemKeyEvents: Int = 0
    private var processNameLookups: Int = 0
    private var hotkeyLookups: Int = 0
    private var hotkeyFound: Int = 0
    private var hotkeyNotFound: Int = 0
    private var keysForwarded: Int = 0
    private var commandsExecuted: Int = 0
    private var blacklistedExits: Int = 0
    private var selfGeneratedExits: Int = 0
    private var noModeExits: Int = 0

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public func traceKeyEvent()          { guard enabled else { return }; totalKeyEvents += 1 }
    public func traceKeyDown()           { guard enabled else { return }; keyDownEvents += 1 }
    public func traceSystemKey()         { guard enabled else { return }; systemKeyEvents += 1 }
    public func traceProcessNameLookup() { guard enabled else { return }; processNameLookups += 1 }
    public func traceHotkeyLookup()      { guard enabled else { return }; hotkeyLookups += 1 }
    public func traceHotkeyFound()       { guard enabled else { return }; hotkeyFound += 1 }
    public func traceHotkeyNotFound()    { guard enabled else { return }; hotkeyNotFound += 1 }
    public func traceKeyForwarded()      { guard enabled else { return }; keysForwarded += 1 }
    public func traceCommandExecuted()   { guard enabled else { return }; commandsExecuted += 1 }
    public func traceBlacklisted()       { guard enabled else { return }; blacklistedExits += 1 }
    public func traceSelfGenerated()     { guard enabled else { return }; selfGeneratedExits += 1 }
    public func traceNoMode()            { guard enabled else { return }; noModeExits += 1 }

    public func printSummary() {
        guard enabled else { return }
        print("""
        --- SwiftKHD Profiling Summary ---
        Total key events:     \(totalKeyEvents)
          key down:           \(keyDownEvents)
          system (media):     \(systemKeyEvents)
        Process lookups:      \(processNameLookups)
        Hotkey lookups:       \(hotkeyLookups)
          found:              \(hotkeyFound)
          not found:          \(hotkeyNotFound)
        Actions:
          commands executed:  \(commandsExecuted)
          keys forwarded:     \(keysForwarded)
        Early exits:
          no mode:            \(noModeExits)
          blacklisted:        \(blacklistedExits)
          self-generated:     \(selfGeneratedExits)
        """)
        if hotkeyLookups > 0 {
            let hitRate = Double(hotkeyFound) / Double(hotkeyLookups) * 100
            print("Hotkey hit rate: \(String(format: "%.1f", hitRate))%")
        }
    }
}
