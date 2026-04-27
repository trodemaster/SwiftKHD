import ArgumentParser
import Foundation

struct SwiftKHD: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftkhd",
        abstract: "Simple Hotkey Daemon for macOS (Swift port of skhd)",
        discussion: """
        NOTE: By default macOS maps F1-F20 to system functions (brightness, volume, etc.).
        To bind function keys directly, enable System Settings → Keyboard →
        "Use F1, F2, etc. keys as standard function keys", or prefix the key
        with the fn modifier (e.g. fn - f1).
        """,
        version: "0.1.5"
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

        return try promptCreateDefaultConfig(home: home, xdgHome: xdgHome, searched: candidates)
    }

    private func promptCreateDefaultConfig(home: String, xdgHome: String, searched: [String]) throws -> String {
        fputs("swiftkhd: No config file found. Searched:\n", stderr)
        for path in searched { fputs("  \(path)\n", stderr) }
        fputs("\nCreate default config at \(xdgHome)/skhd/skhdrc? [y/N] ", stderr)

        guard let answer = readLine(strippingNewline: true),
              answer.lowercased() == "y" else {
            fputs("Cancelled. Use --config to specify a file.\n", stderr)
            throw ExitCode.success
        }

        let configDir = "\(xdgHome)/skhd"
        let configPath = "\(configDir)/skhdrc"
        try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        try defaultConfigContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        fputs("Created \(configPath)\n\n", stderr)
        return configPath
    }
}
