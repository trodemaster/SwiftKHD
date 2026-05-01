import AppKit
import CoreGraphics
import Foundation
import Darwin

// Self-reference for C signal handlers (same pattern as global_skhd in Zig)
nonisolated(unsafe) var globalDaemon: Daemon? = nil

// Magic marker to avoid processing events we generated ourselves
private let skhdEventMarker: Int64 = 0x736B6864 // "skhd" in hex

// NX_SYSDEFINED event type raw value
private let nxSysDefinedType: CGEventType = CGEventType(rawValue: 14) ?? .null

private enum HotkeyResult {
    case consumed
    case passthrough
    case notFound
}

// MARK: - Daemon

public final class Daemon {
    private var mappings: Mappings
    private var currentModeName: String = "default"
    private let eventTap = EventTap()
    private var appMonitor: AppSwitchMonitor?
    private var fsWatcher: FSWatcher?
    private var configPath: String
    private let verbose: Bool
    public let tracer: Tracer

    // Pipe for safe SIGUSR1 → main-thread reload (internal so the C callback can access it)
    var reloadPipe: (read: Int32, write: Int32) = (-1, -1)
    private var pipeSource: CFRunLoopSource?

    public init(configPath: String, verbose: Bool, profile: Bool) throws {
        self.configPath = configPath
        self.verbose = verbose
        self.tracer = Tracer(enabled: profile)

        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let maps = Mappings()
        let content = try String(contentsOfFile: configPath, encoding: .utf8)
        try parser.parseWithPath(mappings: maps, content: content, filePath: configPath)
        try parser.processLoadDirectives(mappings: maps)
        self.mappings = maps
        self.currentModeName = "default"
    }

    public func run(hotload: Bool) throws {
        globalDaemon = self

        // Set up SIGUSR1 via pipe (async-signal-safe)
        var fds: [Int32] = [0, 0]
        if pipe(&fds) != 0 { throw DaemonError.pipeFailed }
        reloadPipe = (fds[0], fds[1])
        setupSignalPipe()

        // SIGINT → stop run loop for graceful shutdown
        signal(SIGINT) { _ in CFRunLoopStop(CFRunLoopGetMain()) }

        if hotload { try enableHotReload() }

        // Initialize NSWorkspace (replaces NSApplicationLoad)
        let _ = NSWorkspace.shared
        appMonitor = AppSwitchMonitor()

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << nxSysDefinedType.rawValue)

        try eventTap.start(mask: mask) { [weak self] proxy, type, event in
            guard let self else { return event }
            return self.handleEvent(proxy: proxy, type: type, event: event)
        }

        fputs("swiftkhd: event tap created. Running.\n", stderr)
        CFRunLoopRun()
        tracer.printSummary()
    }

    // MARK: - Event handling

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> CGEvent? {
        tracer.traceKeyEvent()
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            return event
        case .keyDown:
            tracer.traceKeyDown()
            return handleKeyDown(event: event)
        case nxSysDefinedType:
            tracer.traceSystemKey()
            return handleSystemKey(event: event)
        default:
            return event
        }
    }

    private func handleKeyDown(event: CGEvent) -> CGEvent? {
        guard mappings.modeMap[currentModeName] != nil else {
            tracer.traceNoMode()
            return event
        }
        // Skip self-generated events
        if event.getIntegerValueField(.eventSourceUserData) == skhdEventMarker {
            tracer.traceSelfGenerated()
            return event
        }

        tracer.traceProcessNameLookup()
        let processName = appMonitor?.processName ?? "unknown"
        if mappings.isBlacklisted(processName) {
            tracer.traceBlacklisted()
            return event
        }

        let keycode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        var flags = cgEventFlagsToModifierFlag(event.flags)
        // F13-F19 are pure function keys with no fn-layer alternate; hardware may or may not
        // set maskSecondaryFn for them, so strip fn_ to get consistent matching against config.
        if pureFunctionKeycodes.contains(keycode) { flags.remove(.fn_) }
        let kp = KeyPress(flags: flags, key: keycode)
        return handleHotkeyResult(processHotkey(kp, event: event, processName: processName), event: event, kp: kp)
    }

    private func handleSystemKey(event: CGEvent) -> CGEvent? {
        guard mappings.modeMap[currentModeName] != nil else {
            tracer.traceNoMode()
            return event
        }
        if event.getIntegerValueField(.eventSourceUserData) == skhdEventMarker {
            tracer.traceSelfGenerated()
            return event
        }

        tracer.traceProcessNameLookup()
        let processName = appMonitor?.processName ?? "unknown"
        if mappings.isBlacklisted(processName) {
            tracer.traceBlacklisted()
            return event
        }

        guard let kp = interceptSystemKey(event) else { return event }
        return handleHotkeyResult(processHotkey(kp, event: event, processName: processName), event: event, kp: kp)
    }

    private func handleHotkeyResult(_ result: HotkeyResult, event: CGEvent, kp: KeyPress) -> CGEvent? {
        switch result {
        case .consumed: return nil
        case .passthrough: return event
        case .notFound:
            if let mode = mappings.modeMap[currentModeName], mode.capture {
                return nil
            }
            return event
        }
    }

    private func processHotkey(_ kp: KeyPress, event: CGEvent, processName: String) -> HotkeyResult {
        guard let mode = mappings.modeMap[currentModeName] else { return .notFound }
        tracer.traceHotkeyLookup()
        guard let hotkey = mode.hotkeyMap.lookup(keyPress: kp) else {
            tracer.traceHotkeyNotFound()
            return .notFound
        }
        tracer.traceHotkeyFound()

        guard let cmd = hotkey.findCommandForProcess(processName) else { return .notFound }

        switch cmd {
        case .command(let command):
            tracer.traceCommandExecuted()
            forkAndExec(shell: mappings.shell, command: command, verbose: verbose)
            return hotkey.flags.contains(.passthrough) ? .passthrough : .consumed

        case .forwarded(let targetKP):
            tracer.traceKeyForwarded()
            forwardKey(targetKP, originalEvent: event)
            return .consumed

        case .unbound:
            return .passthrough

        case .activation(let modeName, let activationCmd):
            if let c = activationCmd {
                forkAndExec(shell: mappings.shell, command: c, verbose: verbose)
            }
            if mappings.modeMap[modeName] != nil {
                currentModeName = modeName
                if let modeCmd = mappings.modeMap[modeName]?.command {
                    forkAndExec(shell: mappings.shell, command: modeCmd, verbose: verbose)
                }
            } else {
                fputs("swiftkhd: mode '\(modeName)' not found, resetting to default\n", stderr)
                currentModeName = "default"
            }
            return .consumed
        }
    }

    // MARK: - Key forwarding

    private func forwardKey(_ target: KeyPress, originalEvent: CGEvent) {
        if target.flags.contains(.nx) {
            postMediaKeyEvent(keyCode: target.key, keyDown: true)
            postMediaKeyEvent(keyCode: target.key, keyDown: false)
            return
        }
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(target.key), keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(target.key), keyDown: false)
        let cgFlags = modifierFlagToCGEventFlags(target.flags)
        down?.flags = cgFlags
        up?.flags   = cgFlags
        down?.setIntegerValueField(.eventSourceUserData, value: skhdEventMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: skhdEventMarker)
        down.map { $0.post(tap: .cgSessionEventTap) }
        up.map   { $0.post(tap: .cgSessionEventTap) }
    }

    // MARK: - NX system key interception

    private func interceptSystemKey(_ event: CGEvent) -> KeyPress? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return nil }
        guard nsEvent.subtype.rawValue == 8 else { return nil } // NX_SUBTYPE_AUX_CONTROL_BUTTONS
        let data1 = nsEvent.data1
        let keyCode = (data1 >> 16) & 0xFF
        let keyState = (data1 >> 8) & 0xFF
        guard keyState == 0x0A else { return nil } // NX_KEYDOWN
        var flags = cgEventFlagsToModifierFlag(event.flags)
        flags.insert(.nx)
        return KeyPress(flags: flags, key: UInt32(keyCode))
    }

    // MARK: - Config reload

    public func reloadConfig() {
        do {
            let keycodes = try Keycodes()
            let parser = Parser(keycodes: keycodes)
            let newMappings = Mappings()
            let content = try String(contentsOfFile: configPath, encoding: .utf8)
            try parser.parseWithPath(mappings: newMappings, content: content, filePath: configPath)
            try parser.processLoadDirectives(mappings: newMappings)
            mappings = newMappings
            if mappings.modeMap["default"] != nil {
                currentModeName = "default"
            }
            fputs("swiftkhd: configuration reloaded.\n", stderr)
        } catch {
            fputs("swiftkhd: reload failed: \(error)\n", stderr)
        }
    }

    // MARK: - Hot reload

    private func enableHotReload() throws {
        let watcher = FSWatcher { [weak self] _ in self?.reloadConfig() }
        let resolved = (configPath as NSString).resolvingSymlinksInPath
        watcher.addFile(resolved)
        for f in mappings.loadedFiles { watcher.addFile(f) }
        try watcher.start()
        fsWatcher = watcher
    }

    // MARK: - Signal pipe (SIGUSR1 → safe main-thread reload)

    private func setupSignalPipe() {
        // Set write end non-blocking
        let wfd = reloadPipe.write
        _ = fcntl(wfd, F_SETFL, fcntl(wfd, F_GETFL) | O_NONBLOCK)

        // SIGUSR1 handler just writes 1 byte to the pipe
        signal(SIGUSR1) { _ in
            var byte: UInt8 = 1
            _ = withUnsafePointer(to: &byte) { Darwin.write(globalDaemon?.reloadPipe.write ?? -1, $0, 1) }
        }

        // Install a CFRunLoopSource watching the read end
        let rfd = reloadPipe.read
        var ctx = CFFileDescriptorContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil
        )
        guard let fdref = CFFileDescriptorCreate(kCFAllocatorDefault, rfd, false, pipeCallback, &ctx) else { return }
        CFFileDescriptorEnableCallBacks(fdref, CFOptionFlags(kCFFileDescriptorReadCallBack))
        guard let src = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, fdref, 0) else { return }
        pipeSource = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, CFRunLoopMode.commonModes)
    }
}

// MARK: - CFFileDescriptor callback (fires on read end of pipe, main thread)
private let pipeCallback: CFFileDescriptorCallBack = { fdref, _, info in
    guard let info else { return }
    let daemon = Unmanaged<Daemon>.fromOpaque(info).takeUnretainedValue()
    // Drain the pipe
    var byte: UInt8 = 0
    _ = withUnsafeMutablePointer(to: &byte) { read(daemon.reloadPipe.read, $0, 1) }
    // Re-arm
    if let fdref { CFFileDescriptorEnableCallBacks(fdref, CFOptionFlags(kCFFileDescriptorReadCallBack)) }
    daemon.reloadConfig()
}

public enum DaemonError: Error {
    case pipeFailed
}
