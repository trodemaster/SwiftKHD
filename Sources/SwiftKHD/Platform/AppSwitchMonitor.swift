import AppKit
import os

/// Monitors the frontmost application and caches its lowercased name.
/// Uses NSWorkspace notifications instead of deprecated Carbon GetFrontProcess APIs.
/// Cache reads are protected by OSAllocatedUnfairLock for thread safety.
public final class AppSwitchMonitor {
    private let lock = OSAllocatedUnfairLock(initialState: "unknown")

    public init() {
        updateCache()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func appDidActivate(_ notification: Notification) {
        updateCache()
    }

    private func updateCache() {
        let name = NSWorkspace.shared.frontmostApplication?.localizedName?.lowercased() ?? "unknown"
        lock.withLock { state in state = name }
    }

    /// Returns the cached lowercased process name. Safe to call from any thread.
    public var processName: String {
        lock.withLock { $0 }
    }
}
