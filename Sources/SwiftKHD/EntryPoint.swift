import ArgumentParser
import Foundation

struct SwiftKHD: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftkhd",
        abstract: "Simple Hotkey Daemon for macOS (Swift port of skhd)",
        version: "0.1.0"
    )

    // MARK: - Arguments

    @Option(name: [.customShort("c"), .long], help: "Specify config file path")
    var config: String?

    @Flag(name: [.customShort("V"), .long], help: "Enable verbose logging")
    var verbose: Bool = false

    @Flag(name: [.customLong("no-hotload"), .customShort("h")], help: "Disable config hot reload")
    var noHotload: Bool = false

    @Flag(name: [.customShort("o"), .long], help: "Observe mode: print raw keyboard events")
    var observe: Bool = false

    @Flag(name: [.customShort("P"), .long], help: "Enable profiling/tracing")
    var profile: Bool = false

    @Option(name: [.customShort("k"), .long], help: "Synthesize a keypress (e.g. 'cmd - a')")
    var key: String?

    @Option(name: [.customShort("t"), .long], help: "Synthesize text input")
    var text: String?

    // Service management
    @Flag(name: .long, help: "Install launchd service")
    var installService: Bool = false

    @Flag(name: .long, help: "Uninstall launchd service")
    var uninstallService: Bool = false

    @Flag(name: .long, help: "Start launchd service")
    var startService: Bool = false

    @Flag(name: .long, help: "Stop launchd service")
    var stopService: Bool = false

    @Flag(name: .long, help: "Restart launchd service")
    var restartService: Bool = false

    @Flag(name: .long, help: "Show service status")
    var status: Bool = false

    @Flag(name: [.customShort("r"), .long], help: "Reload config in running instance")
    var reload: Bool = false

    // MARK: - Run

    mutating func run() throws {
        // Service commands
        if installService   { try ServiceManager.install();   return }
        if uninstallService { try ServiceManager.uninstall(); return }
        if startService     { try ServiceManager.start();     return }
        if stopService      { try ServiceManager.stop();      return }
        if restartService   { try ServiceManager.restart();   return }
        if status           { ServiceManager.status();        return }
        if reload           { try ServiceManager.reloadRunningInstance(); return }

        // Key/text synthesis
        if let k = key   { try synthesizeKey(k); return }
        if let t = text  { synthesizeText(t);    return }

        // Observe mode
        if observe {
            let obs = ObserveMode()
            try obs.run()
            return
        }

        // Resolve config file
        let configPath = try resolveConfigFile(override: config)

        // Check accessibility
        if !ServiceManager.hasAccessibilityPermissions() {
            fputs("""
            swiftkhd: Accessibility permissions required.
            Open System Settings → Privacy & Security → Accessibility and add this binary.
            \n
            """, stderr)
        }

        // Write PID file
        try? ServiceManager.writePidFile()
        defer { ServiceManager.removePidFile() }

        // Start daemon
        let daemon = try Daemon(configPath: configPath, verbose: verbose, profile: profile)
        try daemon.run(hotload: !noHotload)
    }

    private func resolveConfigFile(override: String?) throws -> String {
        if let path = override {
            return (path as NSString).standardizingPath
        }
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? NSHomeDirectory()
        let xdgHome = env["XDG_CONFIG_HOME"] ?? "\(home)/.config"

        let candidates = [
            "\(xdgHome)/skhd/skhdrc",
            "\(home)/.config/skhd/skhdrc",
            "\(home)/.skhdrc",
            "skhdrc",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        throw ConfigError.notFound(candidates)
    }
}

enum ConfigError: Error, CustomStringConvertible {
    case notFound([String])

    var description: String {
        switch self {
        case .notFound(let paths):
            return "No config file found. Searched:\n" + paths.map { "  \($0)" }.joined(separator: "\n")
        }
    }
}
