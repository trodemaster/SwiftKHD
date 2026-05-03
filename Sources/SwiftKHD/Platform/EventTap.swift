import CoreGraphics
import Foundation

public enum EventTapError: Error {
    case accessibilityPermissionDenied
    case tapCreationFailed
}

/// Wraps CGEventTap for capturing keyboard events.
public final class EventTap {
    public typealias Handler = (CGEventTapProxy, CGEventType, CGEvent) -> CGEvent?
    /// Called when macOS disables the tap. `timedOut` is true for a timeout disable,
    /// false when accessibility was revoked. The tap has already been re-enabled if
    /// `timedOut` is true; for revocation the tap stays disabled.
    public var onDisabled: ((_ timedOut: Bool) -> Void)?

    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    deinit { stop() }

    public func start(mask: CGEventMask, handler: @escaping Handler) throws {
        let handlerBox = HandlerBox(handler: handler, onDisabled: onDisabled)
        let userInfo = Unmanaged.passRetained(handlerBox).toOpaque()

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: userInfo
        )
        guard let tap else {
            Unmanaged<HandlerBox>.fromOpaque(userInfo).release()
            throw EventTapError.accessibilityPermissionDenied
        }
        handlerBox.tap = tap
        tapPort = tap

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, CFRunLoopMode.commonModes)
        }
        if let port = tapPort {
            CGEvent.tapEnable(tap: port, enable: false)
        }
        tapPort = nil
        runLoopSource = nil
    }
}

// MARK: - CGEventFlags → ModifierFlag

/// Converts CGEventFlags to ModifierFlag using the same bitmasks as skhd.zig.
public func cgEventFlagsToModifierFlag(_ eventFlags: CGEventFlags) -> ModifierFlag {
    var flags: ModifierFlag = []
    let raw = eventFlags.rawValue

    if eventFlags.contains(.maskAlternate) {
        let lalt = (raw & 0x00000020) != 0
        let ralt = (raw & 0x00000040) != 0
        if lalt { flags.insert(.lalt) }
        if ralt { flags.insert(.ralt) }
        if !lalt && !ralt { flags.insert(.alt) }
    }

    if eventFlags.contains(.maskShift) {
        let lshift = (raw & 0x00000002) != 0
        let rshift = (raw & 0x00000004) != 0
        if lshift { flags.insert(.lshift) }
        if rshift { flags.insert(.rshift) }
        if !lshift && !rshift { flags.insert(.shift) }
    }

    if eventFlags.contains(.maskCommand) {
        let lcmd = (raw & 0x00000008) != 0
        let rcmd = (raw & 0x00000010) != 0
        if lcmd { flags.insert(.lcmd) }
        if rcmd { flags.insert(.rcmd) }
        if !lcmd && !rcmd { flags.insert(.cmd) }
    }

    if eventFlags.contains(.maskControl) {
        let lctrl = (raw & 0x00000001) != 0
        let rctrl = (raw & 0x00002000) != 0
        if lctrl { flags.insert(.lcontrol) }
        if rctrl { flags.insert(.rcontrol) }
        if !lctrl && !rctrl { flags.insert(.control) }
    }

    if eventFlags.contains(.maskSecondaryFn) { flags.insert(.fn_) }

    return flags
}

// MARK: - Internal

private final class HandlerBox {
    let handler: EventTap.Handler
    let onDisabled: ((_ timedOut: Bool) -> Void)?
    var tap: CFMachPort?
    init(handler: @escaping EventTap.Handler, onDisabled: ((_ timedOut: Bool) -> Void)?) {
        self.handler = handler
        self.onDisabled = onDisabled
    }
}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo -> Unmanaged<CGEvent>? in
    guard let userInfo else { return Unmanaged.passRetained(event) }
    let box = Unmanaged<HandlerBox>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout {
        if let tap = box.tap { CGEvent.tapEnable(tap: tap, enable: true) }
        box.onDisabled?(true)
        return Unmanaged.passRetained(event)
    }

    if type == .tapDisabledByUserInput {
        // Accessibility was revoked — re-enable will not succeed; notify caller to exit.
        box.onDisabled?(false)
        return Unmanaged.passRetained(event)
    }

    if let result = box.handler(proxy, type, event) {
        return Unmanaged.passRetained(result)
    }
    return nil
}
