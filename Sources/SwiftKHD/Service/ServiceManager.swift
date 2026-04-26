import ApplicationServices
import Foundation
import Darwin

public enum ServiceManager {
    private static let label    = "com.netjibbing.SwiftKHD"
    private static let plistName = "\(label).plist"

    private static let launchAgentsDir: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/LaunchAgents"
    }()
    private static var plistPath: String { "\(launchAgentsDir)/\(plistName)" }

    private static let pidFileName: String = {
        let user = ProcessInfo.processInfo.environment["USER"] ?? "user"
        return "/tmp/swiftkHD_\(user).pid"
    }()

    // MARK: - Plist generation

    private static func binaryPath() -> String {
        let arg0 = CommandLine.arguments[0]
        // Already absolute
        if arg0.hasPrefix("/") {
            return (arg0 as NSString).standardizingPath
        }
        // Resolve bare name against PATH
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        for dir in pathDirs {
            let candidate = (dir as NSString).appendingPathComponent(arg0)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return (candidate as NSString).standardizingPath
            }
        }
        // Fallback: resolve against current working directory
        return (FileManager.default.currentDirectoryPath as NSString)
            .appendingPathComponent(arg0)
    }

    private static var logPath: String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/Logs/swiftkHD.log"
    }

    private static func generatePlist(binaryPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>Program</key>
            <string>\(binaryPath)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
            <key>ThrottleInterval</key>
            <integer>30</integer>
            <key>StandardOutPath</key>
            <string>\(logPath)</string>
            <key>StandardErrorPath</key>
            <string>\(logPath)</string>
        </dict>
        </plist>
        """
    }

    // MARK: - launchctl helpers

    private static var gui: String { "gui/\(getuid())" }

    @discardableResult
    private static func launchctl(_ args: [String], ignoreFailure: Bool = false) throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = args
        try proc.run()
        proc.waitUntilExit()
        let code = proc.terminationStatus
        if code != 0 && !ignoreFailure {
            throw ServiceError.launchctlFailed(args.joined(separator: " "), code)
        }
        return code
    }

    // MARK: - Service operations

    public static func install() throws {
        try FileManager.default.createDirectory(atPath: launchAgentsDir,
                                                withIntermediateDirectories: true)
        let bin = binaryPath()
        try generatePlist(binaryPath: bin).write(toFile: plistPath, atomically: true, encoding: .utf8)
        try launchctl(["bootstrap", gui, plistPath], ignoreFailure: true)
        print("swiftkHD: service installed. Grant Accessibility in System Settings → Privacy & Security → Accessibility.")
    }

    public static func uninstall() throws {
        try launchctl(["bootout", gui, plistPath], ignoreFailure: true)
        try? FileManager.default.removeItem(atPath: plistPath)
        print("swiftkHD: service uninstalled.")
    }

    public static func start() throws {
        try launchctl(["kickstart", "\(gui)/\(label)"])
    }

    public static func stop() throws {
        try launchctl(["kill", "SIGTERM", "\(gui)/\(label)"])
    }

    public static func restart() throws {
        try launchctl(["kickstart", "-k", "\(gui)/\(label)"])
    }

    public static func status() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["print", "\(gui)/\(label)"]
        try? proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            print("swiftkHD: service not loaded. Run --install-service to install.")
        }
    }

    // MARK: - PID file

    public static func writePidFile() throws {
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        try pid.write(toFile: pidFileName, atomically: true, encoding: .utf8)
    }

    public static func removePidFile() {
        try? FileManager.default.removeItem(atPath: pidFileName)
    }

    public static func readPidFile() throws -> pid_t? {
        guard let content = try? String(contentsOfFile: pidFileName, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    public static func isRunning(pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    // MARK: - Reload running instance

    public static func reloadRunningInstance() throws {
        guard let pid = try readPidFile() else {
            throw ServiceError.notRunning
        }
        guard isRunning(pid: pid) else {
            throw ServiceError.notRunning
        }
        if kill(pid, SIGUSR1) != 0 {
            throw ServiceError.signalFailed
        }
    }

    // MARK: - Accessibility check

    public static func hasAccessibilityPermissions() -> Bool {
        AXIsProcessTrusted()
    }
}

public enum ServiceError: Error, CustomStringConvertible {
    case notRunning
    case signalFailed
    case launchctlFailed(String, Int32)

    public var description: String {
        switch self {
        case .notRunning:
            return "swiftkHD does not appear to be running"
        case .signalFailed:
            return "Failed to send reload signal"
        case .launchctlFailed(let cmd, let code):
            return "launchctl \(cmd) failed (exit \(code))"
        }
    }
}
