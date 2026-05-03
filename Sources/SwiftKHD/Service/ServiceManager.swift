import ApplicationServices
import Foundation
import Darwin
import Security

public enum ServiceManager {
    private static let label    = "com.netjibbing.swiftkhd"
    private static let plistName = "\(label).plist"

    private static let launchAgentsDir: String = {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return "\(home)/Library/LaunchAgents"
    }()
    private static var plistPath: String { "\(launchAgentsDir)/\(plistName)" }

    private static let pidFileName: String = {
        let user = ProcessInfo.processInfo.environment["USER"] ?? "user"
        return "/tmp/swiftkhd_\(user).pid"
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
        let home = FileManager.default.homeDirectoryForCurrentUser
            .standardized.resolvingSymlinksInPath().path
        return "\(home)/Library/Logs/swiftkhd.log"
    }

    private static func generatePlist(binaryPath: String) -> String {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>
            <key>Program</key>
            <string>\(binaryPath)</string>
            <key>EnvironmentVariables</key>
            <dict>
                <key>PATH</key>
                <string>\(path)</string>
            </dict>
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
        let fm = FileManager.default
        try fm.createDirectory(atPath: launchAgentsDir, withIntermediateDirectories: true)
        let log = logPath
        try fm.createDirectory(atPath: (log as NSString).deletingLastPathComponent,
                               withIntermediateDirectories: true)
        let bin = binaryPath()
        try generatePlist(binaryPath: bin).write(toFile: plistPath, atomically: true, encoding: .utf8)
        try launchctl(["bootstrap", gui, plistPath], ignoreFailure: true)
        print("swiftkhd: service installed.")
        if !hasAccessibilityPermissions() {
            print("swiftkhd: Requesting accessibility permissions...")
            requestAccessibilityPermissions()
            print("swiftkhd: Grant access in the dialog that appeared, then restart the service with --restart-service.")
        }
    }

    public static func uninstall() throws {
        try launchctl(["bootout", gui, plistPath], ignoreFailure: true)
        try? FileManager.default.removeItem(atPath: plistPath)
        print("swiftkhd: service uninstalled.")
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
            print("swiftkhd: service not loaded. Run --install-service to install.")
        }
        printAccessibilityDiagnostics()
    }

    // MARK: - Accessibility diagnostics

    private static func printAccessibilityDiagnostics() {
        print("")
        print("Accessibility diagnostics:")

        // AXIsProcessTrusted for this (CLI) process
        let trusted = AXIsProcessTrusted()
        print("  AXIsProcessTrusted:   \(trusted ? "yes" : "no")")

        // CDHash of the installed binary
        let binPath = binaryPath()
        let binHash = cdHash(ofPath: binPath)
        print("  Binary:               \(binPath)")
        print("  Binary CDHash:        \(binHash ?? "(unreadable)")")

        // CDHash of the running daemon (via PID file)
        if let pid = (try? readPidFile()) ?? nil, isRunning(pid: pid) {
            let daemonHash = cdHash(ofPid: pid)
            print("  Daemon PID:           \(pid)")
            print("  Daemon CDHash:        \(daemonHash ?? "(unreadable)")")
            if let bh = binHash, let dh = daemonHash {
                if bh == dh {
                    print("  Binary/daemon match:  yes")
                } else {
                    print("  Binary/daemon match:  NO — daemon is running a different binary than installed")
                }
            }
        } else {
            print("  Daemon:               not running")
        }

        // TCC database entry
        print("  TCC entry:")
        switch readTCCEntry(binaryPath: binPath) {
        case .noAccess:
            print("    cannot read TCC database (try: sudo swiftkhd --status)")
        case .notFound:
            print("    not found — accessibility has never been granted for this binary")
        case .found(let client, let auth, let tccHash):
            let authLabel = auth == 2 ? "allowed" : auth == 0 ? "denied" : "unknown (\(auth))"
            print("    client:  \(client)")
            print("    auth:    \(authLabel)")
            if let th = tccHash {
                print("    CDHash:  \(th)")
                if let bh = binHash {
                    if th == bh {
                        print("    match:   yes ✓")
                    } else {
                        print("    match:   NO ✗ — binary was replaced since permission was granted")
                        print("    fix:     System Settings > Privacy & Security > Accessibility")
                        print("             Remove SwiftKHD, re-add it, then: swiftkhd --restart-service")
                    }
                }
            } else {
                print("    CDHash:  (could not parse from stored requirement)")
            }
        }
    }

    private enum TCCResult {
        case notFound
        case noAccess
        case found(client: String, auth: Int, cdHash: String?)
    }

    private static func cdHash(ofPath path: String) -> String? {
        var sc: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &sc) == errSecSuccess,
              let sc else { return nil }
        return cdHashFromStaticCode(sc)
    }

    private static func cdHash(ofPid pid: pid_t) -> String? {
        var code: SecCode?
        let attrs = [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else { return nil }
        var sc: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &sc) == errSecSuccess, let sc else { return nil }
        return cdHashFromStaticCode(sc)
    }

    private static func cdHashFromStaticCode(_ sc: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(sc, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any],
              let unique = dict[kSecCodeInfoUnique as String] as? Data else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    private static func readTCCEntry(binaryPath: String) -> TCCResult {
        let home = NSHomeDirectory()
        let dbs = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Application Support/com.apple.TCC/TCC.db",
        ]
        var anyReadable = false
        for db in dbs {
            guard FileManager.default.fileExists(atPath: db) else { continue }
            guard canQuerySQLite(path: db) else { continue }
            anyReadable = true
            if let r = queryTCCForSwiftKHD(db: db) { return r }
        }
        return anyReadable ? .notFound : .noAccess
    }

    private static func canQuerySQLite(path: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [path, "SELECT 1;"]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private static func queryTCCForSwiftKHD(db: String) -> TCCResult? {
        // Broad search: find any accessibility entry whose client contains "swiftkhd"
        let query = "SELECT client, auth_value, hex(csreq) FROM access WHERE service='kTCCServiceAccessibility' AND client LIKE '%swiftkhd%' COLLATE NOCASE LIMIT 1;"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        p.arguments = [db, query]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let raw = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        let parts = line.components(separatedBy: "|")
        guard parts.count >= 2, let auth = Int(parts[1]) else { return nil }
        let client = parts[0]
        let cdHash = parts.count >= 3 ? parseCDHashFromCSReqHex(parts[2]) : nil
        return .found(client: client, auth: auth, cdHash: cdHash)
    }

    private static func parseCDHashFromCSReqHex(_ hex: String) -> String? {
        guard hex.count % 2 == 0, !hex.isEmpty else { return nil }
        var data = Data(capacity: hex.count / 2)
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let byte = UInt8(hex[idx..<next], radix: 16) else { return nil }
            data.append(byte)
            idx = next
        }
        var req: SecRequirement?
        guard SecRequirementCreateWithData(data as CFData, [], &req) == errSecSuccess, let req else { return nil }
        var cfStr: CFString?
        guard SecRequirementCopyString(req, [], &cfStr) == errSecSuccess, let reqString = cfStr as String? else { return nil }
        // Requirement looks like: cdhash H"<hex>"
        if let hStart = reqString.range(of: "H\"")?.upperBound,
           let hEnd = reqString[hStart...].firstIndex(of: "\"") {
            return String(reqString[hStart..<hEnd])
        }
        return reqString
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

    /// Requests accessibility permissions, showing the system dialog.
    /// Only works when called from a foreground process with a TTY.
    @discardableResult
    public static func requestAccessibilityPermissions() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func isRunningInteractively() -> Bool {
        isatty(STDIN_FILENO) != 0
    }
}

public enum ServiceError: Error, CustomStringConvertible {
    case notRunning
    case signalFailed
    case launchctlFailed(String, Int32)

    public var description: String {
        switch self {
        case .notRunning:
            return "swiftkhd does not appear to be running"
        case .signalFailed:
            return "Failed to send reload signal"
        case .launchctlFailed(let cmd, let code):
            return "launchctl \(cmd) failed (exit \(code))"
        }
    }
}
