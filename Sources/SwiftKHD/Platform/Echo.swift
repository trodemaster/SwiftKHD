import CoreGraphics
import Foundation

/// Observe mode: prints raw key events with their keycodes and flags.
/// Mirrors skhd.zig's observe mode (-o flag).
public final class ObserveMode {
    private let eventTap = EventTap()

    public init() {}

    public func run() throws {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        try eventTap.start(mask: mask) { _, type, event in
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = cgEventFlagsToModifierFlag(event.flags)
            let flagsDesc = flags.description.isEmpty ? "(none)" : flags.description
            print("keycode: 0x\(String(keycode, radix: 16, uppercase: false)) (\(keycode)) | flags: \(flagsDesc)")
            return event
        }

        print("Observing key events. Press Ctrl-C to exit.")
        CFRunLoopRun()
    }
}
