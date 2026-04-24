import CoreServices
import Foundation

/// Watches config files for changes using FSEvents.
/// Uses FSEventStreamSetDispatchQueue (not deprecated ScheduleWithRunLoop).
public final class FSWatcher {
    public typealias Callback = (String) -> Void

    private var stream: FSEventStreamRef?
    private let callback: Callback
    // internal so the C callback (file-scope) can access it via the same module
    var watchedFiles: [(absolute: String, resolved: String)] = []

    public init(callback: @escaping Callback) {
        self.callback = callback
    }

    deinit { stop() }

    public func addFile(_ path: String) {
        let resolved = (path as NSString).resolvingSymlinksInPath
        watchedFiles.append((path, resolved))
    }

    public func start() throws {
        guard !watchedFiles.isEmpty else { return }

        var dirs = Set<String>()
        for entry in watchedFiles {
            dirs.insert((entry.resolved as NSString).deletingLastPathComponent)
        }

        let cfPaths = Array(dirs) as CFArray
        var ctx = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )

        let s = FSEventStreamCreate(
            kCFAllocatorDefault,
            fseventsCallback,
            &ctx,
            cfPaths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        )
        guard let s else { throw FSWatcherError.streamCreationFailed }
        stream = s
        FSEventStreamSetDispatchQueue(s, DispatchQueue.main)
        FSEventStreamStart(s)
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    // Called from the C callback
    func fireCallback(for changedPath: String) {
        for entry in watchedFiles where entry.resolved == changedPath {
            callback(entry.resolved)
            break
        }
    }
}

private let fseventsCallback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
    guard let info else { return }
    let watcher = Unmanaged<FSWatcher>.fromOpaque(info).takeUnretainedValue()
    let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    for i in 0..<numEvents {
        let changedPath = String(cString: paths[i])
        watcher.fireCallback(for: changedPath)
    }
}

public enum FSWatcherError: Error {
    case streamCreationFailed
}
