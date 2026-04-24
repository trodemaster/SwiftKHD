import Foundation

// MARK: - CommandDef

public struct CommandDef {
    public enum Part {
        case text(String)
        case placeholder(Int)  // 1-based
    }
    public var parts: [Part]
    public var maxPlaceholder: Int
}

// MARK: - LoadDirective

private struct LoadDirective {
    let filename: String
    let token: Token
}

// MARK: - Parser

public final class Parser {
    private var tokenizer: Tokenizer
    private var previousToken: Token?
    private var nextToken: Token?
    private let keycodes: Keycodes
    private var loadDirectives: [LoadDirective] = []
    private var currentFilePath: String?
    public private(set) var errorInfo: ParseError?
    public private(set) var processGroups: [String: [String]] = [:]
    public private(set) var commandDefs: [String: CommandDef] = [:]

    public init(keycodes: Keycodes) {
        self.keycodes = keycodes
        self.tokenizer = Tokenizer(buffer: "")
    }

    // MARK: - Public API

    public func parse(mappings: Mappings, content: String) throws {
        try parseWithPath(mappings: mappings, content: content, filePath: nil)
    }

    public func parseWithPath(mappings: Mappings, content: String, filePath: String?) throws {
        tokenizer = Tokenizer(buffer: content)
        currentFilePath = filePath
        previousToken = nil
        nextToken = nil
        loadDirectives = []

        // Ensure default mode exists
        if mappings.modeMap["default"] == nil {
            mappings.modeMap["default"] = Mode(name: "default")
        }

        advance()
        while let token = peek() {
            switch token.type {
            case .identifier, .modifier, .literal, .keyHex, .key, .activate:
                do {
                    try parseHotkey(mappings: mappings)
                } catch {
                    if errorInfo == nil {
                        errorInfo = ParseError(message: "Failed to parse hotkey", line: token.line,
                                               column: token.column, filePath: currentFilePath)
                    }
                    throw error
                }
            case .decl:
                do {
                    try parseModeDecl(mappings: mappings)
                } catch {
                    if errorInfo == nil {
                        errorInfo = ParseError(message: "Failed to parse mode declaration", line: token.line,
                                               column: token.column, filePath: currentFilePath)
                    }
                    throw error
                }
            case .option:
                do {
                    try parseOption(mappings: mappings)
                } catch {
                    if errorInfo == nil {
                        errorInfo = ParseError(message: "Failed to parse option", line: token.line,
                                               column: token.column, filePath: currentFilePath)
                    }
                    throw error
                }
            default:
                let msg = "Unexpected token type: \(token.type), text: '\(token.text)'"
                errorInfo = ParseError(message: msg, line: token.line, column: token.column,
                                       filePath: currentFilePath)
                throw ParseError(message: msg, line: token.line, column: token.column,
                                 filePath: currentFilePath)
            }
        }
    }

    public func processLoadDirectives(mappings: Mappings) throws {
        for directive in loadDirectives {
            let resolvedPath = resolveLoadPath(directive.filename)
            let content: String
            do {
                content = try String(contentsOfFile: resolvedPath, encoding: .utf8)
            } catch {
                let msg = "Could not open included file '\(resolvedPath)'"
                let err = ParseError(message: msg, line: directive.token.line,
                                     column: directive.token.column, filePath: currentFilePath)
                errorInfo = err
                throw err
            }

            let absPath = (resolvedPath as NSString).resolvingSymlinksInPath
            mappings.loadedFiles.append(absPath)

            let subParser = Parser(keycodes: keycodes)
            try subParser.parseWithPath(mappings: mappings, content: content, filePath: resolvedPath)
            try subParser.processLoadDirectives(mappings: mappings)
        }
    }

    // MARK: - Token stream

    private func peek() -> Token? { nextToken }

    private func previous() -> Token { previousToken! }

    private func advance() {
        previousToken = nextToken
        nextToken = tokenizer.nextToken()
    }

    private func peekCheck(_ type: TokenType) -> Bool {
        peek()?.type == type
    }

    private func match(_ type: TokenType) -> Bool {
        if peekCheck(type) { advance(); return true }
        return false
    }

    // MARK: - Hotkey parsing

    private func parseHotkey(mappings: Mappings) throws {
        let hotkey = Hotkey()
        var assignedModes: [String] = []

        // Optional mode prefix: identifier(s) < ...
        if match(.identifier) {
            assignedModes = try parseMode(mappings: mappings, hotkey: hotkey)
        }

        if !assignedModes.isEmpty {
            guard match(.insert) else {
                let token = peek() ?? previous()
                throw makeError("Expected '<' after mode identifier", token: token)
            }
        } else {
            // Use default mode
            guard let defaultMode = mappings.modeMap["default"] else {
                let token = peek() ?? previous()
                throw makeError("Default mode not found", token: token)
            }
            assignedModes = ["default"]
            _ = defaultMode
        }

        // Optional modifier(s)
        let foundModifier = match(.modifier)
        if foundModifier {
            hotkey.flags = try parseModifier()
        }

        if foundModifier {
            guard match(.dash) else {
                let token = peek() ?? previous()
                throw makeError("Expected '-' after modifier", token: token)
            }
        }

        // Key
        if match(.key) {
            hotkey.key = try parseKey()
        } else if match(.keyHex) {
            hotkey.key = try parseKeyHex()
        } else if match(.literal) {
            let kp = try parseKeyLiteral()
            hotkey.flags = ModifierFlag(rawValue: hotkey.flags.rawValue | kp.flags.rawValue)
            hotkey.key = kp.key
        } else {
            let token = peek() ?? previous()
            throw makeError("Expected key, key hex, or literal", token: token)
        }

        // Passthrough arrow
        if match(.arrow) {
            hotkey.flags = ModifierFlag(rawValue: hotkey.flags.rawValue | ModifierFlag.passthrough.rawValue)
        }

        // Action
        if match(.activate) {
            let modeName = previous().text
            if match(.command) {
                let result = try parseCommand()
                try hotkey.addProcessActivation("*", modeName: modeName, command: result.command)
            } else {
                try hotkey.addProcessActivation("*", modeName: modeName, command: nil)
            }
        } else if match(.forward) {
            let kp = try parseKeypress()
            try hotkey.addProcessForward("*", keyPress: kp)
        } else if match(.command) {
            let result = try parseCommand()
            try hotkey.addProcessCommand("*", command: result.command)
        } else if match(.unbound) {
            try hotkey.addProcessUnbound("*")
        } else if match(.beginList) {
            try parseProcList(mappings: mappings, hotkey: hotkey)
        }

        // Add hotkey to all assigned modes
        for modeName in assignedModes {
            guard let mode = mappings.modeMap[modeName] else { continue }
            do {
                try mode.addHotkey(hotkey)
            } catch HotkeyError.duplicateHotkeyInMode {
                let keyStr = formatKeyPress(flags: hotkey.flags, key: hotkey.key)
                let msg = "Duplicate hotkey '\(keyStr)' already exists in mode '\(modeName)'"
                let token = previous()
                throw makeError(msg, token: token)
            }
        }
    }

    private func parseMode(mappings: Mappings, hotkey: Hotkey) throws -> [String] {
        let token = previous()
        assert(token.type == .identifier)
        let name = token.text

        guard let mode = mappings.modeMap[name] else {
            let msg = "Mode '\(name)' not found. Did you forget to declare it with '::\(name)'?"
            throw makeError(msg, token: token)
        }
        _ = mode
        var names = [name]

        if match(.comma) {
            guard match(.identifier) else {
                let t = peek() ?? previous()
                throw makeError("Expected mode identifier after comma", token: t)
            }
            names += try parseMode(mappings: mappings, hotkey: hotkey)
        }
        return names
    }

    private func parseModifier() throws -> ModifierFlag {
        let token = previous()
        guard var flags = ModifierFlag.named(token.text) else {
            throw makeError("Unknown modifier '\(token.text)'", token: token)
        }
        if match(.plus) {
            guard match(.modifier) else {
                let t = peek() ?? previous()
                throw makeError("Expected modifier after '+'", token: t)
            }
            let more = try parseModifier()
            flags = ModifierFlag(rawValue: flags.rawValue | more.rawValue)
        }
        return flags
    }

    private func parseKey() throws -> UInt32 {
        let token = previous()
        do {
            return try keycodes.getKeycode(token.text)
        } catch KeycodesError.keyNotFound {
            throw makeError("Unknown key '\(token.text)'", token: token)
        }
    }

    private func parseKeyHex() throws -> UInt32 {
        let token = previous()
        guard let code = UInt32(token.text, radix: 16) else {
            throw makeError("Invalid hex keycode '0x\(token.text)'", token: token)
        }
        return code
    }

    private func parseKeyLiteral() throws -> KeyPress {
        let token = previous()
        for (i, literal) in literalKeycodeStr.enumerated() {
            if token.text == literal {
                var flags: ModifierFlag = []
                if i > keyHasImplicitFnMod && i < keyHasImplicitNxMod {
                    flags = .fn_
                } else if i >= keyHasImplicitNxMod {
                    flags = .nx
                }
                return KeyPress(flags: flags, key: literalKeycodeValue[i])
            }
        }
        throw makeError("Unknown literal key '\(token.text)'", token: token)
    }

    private func parseKeypress() throws -> KeyPress {
        var flags: ModifierFlag = []
        var keycode: UInt32 = 0
        let foundModifier = match(.modifier)
        if foundModifier {
            flags = try parseModifier()
            guard match(.dash) else {
                let t = peek() ?? previous()
                throw makeError("Expected '-' after modifier", token: t)
            }
        }
        if match(.key) {
            keycode = try parseKey()
        } else if match(.keyHex) {
            keycode = try parseKeyHex()
        } else if match(.literal) {
            let kp = try parseKeyLiteral()
            flags = ModifierFlag(rawValue: flags.rawValue | kp.flags.rawValue)
            keycode = kp.key
        } else {
            let t = peek() ?? previous()
            throw makeError("Expected key, key hex, or literal", token: t)
        }
        return KeyPress(flags: flags, key: keycode)
    }

    // MARK: - Process list parsing

    private func parseProcList(mappings: Mappings, hotkey: Hotkey) throws {
        if match(.string) {
            let nameToken = previous()
            let processName = processStringEscapes(nameToken.text)
            if match(.command) {
                let result = try parseCommand()
                do {
                    try hotkey.addProcessCommand(processName, command: result.command)
                } catch {
                    try handleProcessError(error, processName: processName, operation: "command")
                }
            } else if match(.forward) {
                let kp = try parseKeypress()
                do {
                    try hotkey.addProcessForward(processName, keyPress: kp)
                } catch {
                    try handleProcessError(error, processName: processName, operation: "key forward")
                }
            } else if match(.unbound) {
                do {
                    try hotkey.addProcessUnbound(processName)
                } catch {
                    try handleProcessError(error, processName: processName, operation: "unbound action")
                }
            } else if match(.activate) {
                let modeName = previous().text
                if match(.command) {
                    let result = try parseCommand()
                    do {
                        try hotkey.addProcessActivation(processName, modeName: modeName, command: result.command)
                    } catch {
                        try handleProcessError(error, processName: processName, operation: "mode activation")
                    }
                } else {
                    do {
                        try hotkey.addProcessActivation(processName, modeName: modeName, command: nil)
                    } catch {
                        try handleProcessError(error, processName: processName, operation: "mode activation")
                    }
                }
            } else {
                let t = peek() ?? previous()
                throw makeError("Expected ':', '|', '~', or ';' after process name", token: t)
            }
            try parseProcList(mappings: mappings, hotkey: hotkey)

        } else if peekCheck(.reference) {
            advance()
            let refToken = previous()
            let refName = refToken.text

            if peekCheck(.beginTuple) {
                let msg = "Command invocation '@\(refName)(...)' not allowed here. Use process names, wildcards, or process groups"
                throw makeError(msg, token: refToken)
            }

            guard let processes = processGroups[refName] else {
                throw makeError("Undefined process group '@\(refName)'", token: refToken)
            }

            if match(.command) {
                let result = try parseCommand()
                for proc in processes {
                    do {
                        try hotkey.addProcessCommand(proc, command: result.command)
                    } catch {
                        try handleProcessError(error, processName: proc, operation: "command")
                    }
                }
            } else if match(.forward) {
                let kp = try parseKeypress()
                for proc in processes {
                    do {
                        try hotkey.addProcessForward(proc, keyPress: kp)
                    } catch {
                        try handleProcessError(error, processName: proc, operation: "key forward")
                    }
                }
            } else if match(.unbound) {
                for proc in processes {
                    do {
                        try hotkey.addProcessUnbound(proc)
                    } catch {
                        try handleProcessError(error, processName: proc, operation: "unbound action")
                    }
                }
            } else if match(.activate) {
                let modeName = previous().text
                var activationCommand: String? = nil
                if match(.command) {
                    let result = try parseCommand()
                    activationCommand = result.command
                }
                for proc in processes {
                    do {
                        try hotkey.addProcessActivation(proc, modeName: modeName, command: activationCommand)
                    } catch {
                        try handleProcessError(error, processName: proc, operation: "mode activation")
                    }
                }
            } else {
                let t = peek() ?? previous()
                throw makeError("Expected ':', '|', '~', or ';' after process group", token: t)
            }
            try parseProcList(mappings: mappings, hotkey: hotkey)

        } else if match(.wildcard) {
            if match(.command) {
                let result = try parseCommand()
                do {
                    try hotkey.addProcessCommand("*", command: result.command)
                } catch {
                    try handleProcessError(error, processName: "*", operation: "command")
                }
            } else if match(.forward) {
                let kp = try parseKeypress()
                do {
                    try hotkey.addProcessForward("*", keyPress: kp)
                } catch {
                    try handleProcessError(error, processName: "*", operation: "key forward")
                }
            } else if match(.unbound) {
                do {
                    try hotkey.addProcessUnbound("*")
                } catch {
                    try handleProcessError(error, processName: "*", operation: "unbound action")
                }
            } else if match(.activate) {
                let modeName = previous().text
                if match(.command) {
                    let result = try parseCommand()
                    do {
                        try hotkey.addProcessActivation("*", modeName: modeName, command: result.command)
                    } catch {
                        try handleProcessError(error, processName: "*", operation: "mode activation")
                    }
                } else {
                    do {
                        try hotkey.addProcessActivation("*", modeName: modeName, command: nil)
                    } catch {
                        try handleProcessError(error, processName: "*", operation: "mode activation")
                    }
                }
            } else {
                let t = peek() ?? previous()
                throw makeError("Expected ':', '|', '~', or ';' after wildcard", token: t)
            }
            try parseProcList(mappings: mappings, hotkey: hotkey)

        } else if match(.endList) {
            if hotkey.mappings.isEmpty {
                throw makeError("Empty process list", token: previous())
            }
        } else {
            let t = peek() ?? previous()
            throw makeError("Expected process name, wildcard '*' or ']'", token: t)
        }
    }

    // MARK: - Mode declaration

    private func parseModeDecl(mappings: Mappings) throws {
        guard match(.decl) else { fatalError("parseModeDecl called without ::") }
        guard match(.identifier) else {
            let t = peek() ?? previous()
            throw makeError("Expected mode name after '::'", token: t)
        }
        let token = previous()
        let modeName = token.text

        var newMode = Mode(name: modeName)

        if match(.capture) {
            newMode.capture = true
        }

        if match(.command) {
            let result = try parseCommand()
            newMode.command = result.command
        }

        if let existing = mappings.modeMap[modeName] {
            if existing.name == "default" {
                existing.initialized = false
                existing.capture = newMode.capture
                if let cmd = newMode.command { existing.command = cmd }
            } else {
                throw makeError("Mode '\(modeName)' already exists", token: token)
            }
        } else {
            mappings.modeMap[modeName] = newMode
        }
    }

    // MARK: - Command parsing

    private struct CommandResult {
        let command: String
    }

    private func parseCommand() throws -> CommandResult {
        let cmdToken = previous()
        if cmdToken.text.isEmpty {
            // Empty command — must be followed by a reference
            guard peekCheck(.reference) else {
                let t = peek() ?? cmdToken
                throw makeError("Expected command text or command reference after ':'", token: t)
            }
            let cmd = try parseCommandReference()
            return CommandResult(command: cmd)
        }
        return CommandResult(command: cmdToken.text)
    }

    private func parseCommandReference() throws -> String {
        guard match(.reference) else {
            let t = peek() ?? previous()
            throw makeError("Expected command reference", token: t)
        }
        let refToken = previous()
        let commandName = refToken.text

        guard let cmdDef = commandDefs[commandName] else {
            let msg = "Command '@\(commandName)' not found. Did you forget to define it with '.define \(commandName) : ...'?"
            throw makeError(msg, token: refToken)
        }

        if match(.beginTuple) {
            var args: [String] = []
            while true {
                if match(.endTuple) { break }
                guard match(.string) else {
                    let t = peek() ?? previous()
                    let msg = "Command arguments must be enclosed in double quotes in '@\(commandName)'"
                    throw makeError(msg, token: t)
                }
                args.append(processStringEscapes(previous().text))
                if peekCheck(.endTuple) { continue }
                if !match(.comma) {
                    let t = peek() ?? previous()
                    throw makeError("Expected ',' or ')' after argument in command '@\(commandName)'", token: t)
                }
            }

            if args.count != cmdDef.maxPlaceholder {
                let msg: String
                if cmdDef.maxPlaceholder == 0 {
                    msg = "Command '@\(commandName)' expects no arguments but \(args.count) provided"
                } else if args.count < cmdDef.maxPlaceholder {
                    msg = "Command '@\(commandName)' expects \(cmdDef.maxPlaceholder) arguments but only \(args.count) provided"
                } else {
                    msg = "Command '@\(commandName)' expects \(cmdDef.maxPlaceholder) arguments but \(args.count) provided"
                }
                throw makeError(msg, token: refToken)
            }

            return expandTemplate(cmdDef, args: args)
        } else if cmdDef.maxPlaceholder > 0 {
            let msg = "Command '@\(commandName)' expects \(cmdDef.maxPlaceholder) arguments but none provided"
            throw makeError(msg, token: refToken)
        } else {
            return expandTemplate(cmdDef, args: [])
        }
    }

    private func expandTemplate(_ def: CommandDef, args: [String]) -> String {
        var result = ""
        for part in def.parts {
            switch part {
            case .text(let t): result += t
            case .placeholder(let n):
                if n <= args.count { result += args[n - 1] }
            }
        }
        return result
    }

    // MARK: - Options

    private func parseOption(mappings: Mappings) throws {
        guard match(.option) else { fatalError("parseOption called without option token") }
        let option = previous().text

        switch option {
        case "define":
            guard match(.identifier) else {
                let t = peek() ?? previous()
                throw makeError("Expected name after 'define'", token: t)
            }
            let name = previous().text

            if match(.command) {
                // Command definition
                let cmdToken = previous()
                let template = cmdToken.text
                let parsed = try parseCommandTemplate(template, token: cmdToken)
                guard commandDefs[name] == nil else {
                    throw makeError("Command already defined", token: cmdToken)
                }
                commandDefs[name] = parsed
            } else if match(.beginList) {
                // Process group definition
                var processList: [String] = []
                while match(.string) {
                    processList.append(processStringEscapes(previous().text))
                    _ = match(.comma)
                }
                guard match(.endList) else {
                    let t = peek() ?? previous()
                    throw makeError("Expected ']' to close process list", token: t)
                }
                guard processGroups[name] == nil else {
                    throw makeError("Process group already defined", token: previous())
                }
                processGroups[name] = processList
            } else {
                let t = peek() ?? previous()
                throw makeError("Expected ':' for command definition or '[' for process group after name", token: t)
            }

        case "load":
            guard match(.string) else {
                let t = peek() ?? previous()
                throw makeError("Expected filename after 'load'", token: t)
            }
            let filenameToken = previous()
            let filename = processStringEscapes(filenameToken.text)
            loadDirectives.append(LoadDirective(filename: filename, token: filenameToken))

        case "blacklist":
            guard match(.beginList) else {
                let t = peek() ?? previous()
                throw makeError("Expected '[' after 'blacklist'", token: t)
            }
            while match(.string) {
                let appName = processStringEscapes(previous().text)
                mappings.addBlacklist(appName)
            }
            guard match(.endList) else {
                let t = peek() ?? previous()
                throw makeError("Expected ']' to close blacklist", token: t)
            }

        case "shell", "SHELL":
            guard match(.string) else {
                let t = peek() ?? previous()
                throw makeError("Expected shell path after 'shell'", token: t)
            }
            mappings.setShell(processStringEscapes(previous().text))

        default:
            throw makeError("Unknown option '\(option)'. Valid options are: define, load, blacklist, shell",
                            token: previous())
        }
    }

    // MARK: - Command template parsing

    private func parseCommandTemplate(_ template: String, token: Token) throws -> CommandDef {
        var parts: [CommandDef.Part] = []
        var maxPlaceholder = 0
        var idx = template.startIndex

        while idx < template.endIndex {
            // Look for {{
            if template[idx] == "{" {
                let next = template.index(after: idx)
                if next < template.endIndex && template[next] == "{" {
                    // Find closing }}
                    let contentStart = template.index(after: next)
                    var j = contentStart
                    while j < template.endIndex && template[j] != "}" { j = template.index(after: j) }

                    if j < template.endIndex {
                        let afterFirst = template.index(after: j)
                        if afterFirst < template.endIndex && template[afterFirst] == "}" {
                            let numStr = String(template[contentStart..<j])
                            if numStr.isEmpty {
                                throw makeError("Invalid placeholder '{{}}' in command template", token: token)
                            }
                            guard let num = Int(numStr), num > 0 else {
                                if numStr == "0" {
                                    throw makeError("Invalid placeholder '{{0}}' in command template. Placeholders must start from 1.", token: token)
                                }
                                throw makeError("Invalid placeholder '{{\(numStr)}}' in command template. Placeholders must be numbers like {{1}}, {{2}}, etc.", token: token)
                            }
                            parts.append(.placeholder(num))
                            if num > maxPlaceholder { maxPlaceholder = num }
                            idx = template.index(after: afterFirst)
                            continue
                        }
                    }
                }
            }

            // Regular character — find next {{ or end
            var end = template.index(after: idx)
            while end < template.endIndex {
                let c = template[end]
                let nextE = template.index(after: end)
                if c == "{" && nextE < template.endIndex && template[nextE] == "{" { break }
                end = template.index(after: end)
            }
            parts.append(.text(String(template[idx..<end])))
            idx = end
        }

        return CommandDef(parts: parts, maxPlaceholder: maxPlaceholder)
    }

    // MARK: - Helpers

    private func makeError(_ message: String, token: Token) -> ParseError {
        let err = ParseError(message: message, line: token.line, column: token.column,
                             filePath: currentFilePath)
        errorInfo = err
        return err
    }

    /// Process escape sequences: \\ → \, \" → "
    private func processStringEscapes(_ str: String) -> String {
        var result = ""
        var iter = str.makeIterator()
        while let ch = iter.next() {
            if ch == "\\" {
                if let next = iter.next() {
                    if next == "\\" || next == "\"" {
                        result.append(next)
                    } else {
                        result.append(ch)
                        result.append(next)
                    }
                } else {
                    result.append(ch)
                }
            } else {
                result.append(ch)
            }
        }
        return result
    }

    private func resolveLoadPath(_ filename: String) -> String {
        if filename.hasPrefix("/") { return filename }
        if let currentPath = currentFilePath {
            let dir = (currentPath as NSString).deletingLastPathComponent
            return (dir as NSString).appendingPathComponent(filename)
        }
        return filename
    }

    private func handleProcessError(_ error: Error, processName: String, operation: String) throws {
        switch error {
        case HotkeyError.processCommandAlreadyExists:
            let msg: String
            if processName == "*" {
                msg = "Wildcard binding already has a different \(operation). Each hotkey can only have one wildcard action"
            } else {
                msg = "Process '\(processName)' already has a different \(operation) for this hotkey"
            }
            throw makeError(msg, token: previous())
        case HotkeyError.wildcardCommandAlreadyExists:
            throw makeError("This hotkey already has a wildcard \(operation). Only one wildcard action is allowed per hotkey",
                            token: previous())
        default:
            throw error
        }
    }
}
