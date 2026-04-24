import XCTest
@testable import SwiftKHD

final class ParserTests: XCTestCase {

    // Helper: parse content, return Mappings
    private func parse(_ content: String) throws -> Mappings {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let mappings = Mappings()
        try parser.parse(mappings: mappings, content: content)
        return mappings
    }

    private func parseWithError(_ content: String) throws -> (Mappings, Parser) {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let mappings = Mappings()
        try parser.parse(mappings: mappings, content: content)
        return (mappings, parser)
    }

    // MARK: - Basic parsing

    func testBasicHotkey() throws {
        let m = try parse("cmd - a : echo hello")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testMultipleHotkeys() throws {
        let m = try parse("cmd - a : echo a\ncmd - b : echo b")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 2)
    }

    func testHexKey() throws {
        let m = try parse("cmd - 0x00 : echo a")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testLiteralKey() throws {
        let m = try parse("cmd - return : echo return")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    // MARK: - Mode declarations

    func testModeDeclaration() throws {
        let m = try parse(":: window")
        XCTAssertNotNil(m.modeMap["window"])
    }

    func testModeDeclarationWithCapture() throws {
        let m = try parse(":: window @")
        XCTAssertTrue(m.modeMap["window"]?.capture ?? false)
    }

    func testModeDeclarationWithCommand() throws {
        let m = try parse(":: window : echo entered")
        XCTAssertEqual(m.modeMap["window"]?.command, "echo entered")
    }

    func testModeHotkey() throws {
        let m = try parse(":: window\nwindow < cmd - a : echo")
        XCTAssertEqual(m.modeMap["window"]?.hotkeyMap.count, 1)
    }

    func testMultiModeHotkey() throws {
        let m = try parse("""
        :: window
        :: resize
        window, resize < cmd - a : echo
        """)
        XCTAssertEqual(m.modeMap["window"]?.hotkeyMap.count, 1)
        XCTAssertEqual(m.modeMap["resize"]?.hotkeyMap.count, 1)
    }

    // MARK: - Modifiers

    func testLeftRightModifiers() throws {
        let m = try parse("lcmd - a : echo lcmd")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testModifierCombination() throws {
        let m = try parse("cmd + shift - a : echo")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
        let kp = KeyPress(flags: [.cmd, .shift], key: 0) // lookup will fail without actual keycode
        _ = kp
    }

    func testHyperModifier() throws {
        let m = try parse("hyper - a : echo")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    // MARK: - Process lists

    func testProcessList() throws {
        let m = try parse("""
        cmd - a [
            "terminal" : echo terminal
            "safari"   : echo safari
            *          : echo default
        ]
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testProcessListUnbound() throws {
        let m = try parse("""
        cmd - a [
            "terminal" ~
            * : echo default
        ]
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testProcessListForward() throws {
        let m = try parse("""
        cmd - h [
            "terminal" | left
            * : echo default
        ]
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    // MARK: - Key forwarding

    func testKeyForward() throws {
        let m = try parse("cmd - h | left")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    // MARK: - Passthrough / Unbound

    func testPassthrough() throws {
        let m = try parse("cmd - p -> : echo passthrough")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testUnbound() throws {
        let m = try parse("cmd - a ~")
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    // MARK: - Mode activation

    func testModeActivation() throws {
        let m = try parse("""
        :: window
        cmd - w ; window
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testModeActivationWithCommand() throws {
        let m = try parse("""
        :: window
        cmd - w ; window : echo activated
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    // MARK: - Directives

    func testBlacklist() throws {
        let m = try parse(".blacklist [\n\"loginwindow\"\n\"screensaver\"\n]")
        XCTAssertTrue(m.isBlacklisted("loginwindow"))
        XCTAssertTrue(m.isBlacklisted("screensaver"))
        XCTAssertFalse(m.isBlacklisted("terminal"))
    }

    func testShellDirective() throws {
        let m = try parse(".shell \"/bin/zsh\"")
        XCTAssertEqual(m.shell, "/bin/zsh")
    }

    func testShellDirectiveMissing() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: ".shell"))
    }

    // MARK: - Command definitions (.define)

    func testCommandDefNoCholders() throws {
        let m = try parse("""
        .define focus_recent : yabai -m window --focus recent
        cmd - tab : @focus_recent
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testCommandDefSinglePlaceholder() throws {
        let m = try parse("""
        .define focus : yabai -m window --focus {{1}}
        cmd - h : @focus("west")
        cmd - l : @focus("east")
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 2)
    }

    func testCommandDefMultiplePlaceholders() throws {
        let m = try parse("""
        .define swap : yabai -m window --{{1}} {{2}}
        cmd + shift - h : @swap("swap", "west")
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testCommandDefRepeatedPlaceholder() throws {
        let m = try parse("""
        .define notify : osascript -e 'display notification "{{1}}" with title "{{1}}"'
        cmd - n : @notify("Test")
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testCommandDefWrongArgCount() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: """
        .define focus : yabai {{1}} {{2}}
        cmd - h : @focus("only_one")
        """))
        XCTAssertTrue(parser.errorInfo?.message.contains("expects 2 arguments but only 1 provided") ?? false)
    }

    func testCommandDefMissingArgs() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: """
        .define focus : yabai {{1}}
        cmd - h : @focus
        """))
        XCTAssertTrue(parser.errorInfo?.message.contains("expects 1 arguments but none provided") ?? false)
    }

    func testCommandDefUndefined() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: "cmd - h : @undefined_cmd"))
        XCTAssertTrue(parser.errorInfo?.message.contains("not found") ?? false)
    }

    func testCommandDefUnquotedArgs() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: """
        .define toggle : open -a "{{1}}"
        cmd - h : @toggle(Firefox)
        """))
        XCTAssertTrue(parser.errorInfo?.message.contains("must be enclosed in double quotes") ?? false)
    }

    func testInvalidPlaceholderZero() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: ".define bad : echo {{0}}"))
        XCTAssertTrue(parser.errorInfo?.message.contains("must start from 1") ?? false)
    }

    func testInvalidPlaceholderEmpty() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: ".define bad : echo {{}}"))
    }

    // MARK: - Process groups (.define)

    func testProcessGroup() throws {
        let m = try parse("""
        .define browsers ["firefox", "chrome", "safari"]
        cmd - b [
            @browsers : echo browser
            * : echo default
        ]
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }

    func testUndefinedProcessGroupError() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: """
        cmd - a [
            @undefined_group : echo fail
        ]
        """))
        XCTAssertTrue(parser.errorInfo?.message.contains("Undefined process group") ?? false)
    }

    // MARK: - Duplicate detection

    func testDuplicateHotkey() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: """
        cmd - a : echo first
        cmd - a : echo second
        """))
        XCTAssertTrue(parser.errorInfo?.message.contains("Duplicate hotkey") ?? false)
    }

    func testDuplicateModeDifferentAllowed() throws {
        let m = try parse("""
        :: window
        :: resize
        window < cmd - a : echo window
        resize < cmd - a : echo resize
        """)
        XCTAssertEqual(m.modeMap["window"]?.hotkeyMap.count, 1)
        XCTAssertEqual(m.modeMap["resize"]?.hotkeyMap.count, 1)
    }

    func testLRModifiersDifferentKeycodes() throws {
        let m = try parse("""
        lcmd - a : echo lcmd
        rcmd - a : echo rcmd
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 2)
    }

    // MARK: - Error messages

    func testErrorWithLineInfo() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: "cmd - "))
        XCTAssertNotNil(parser.errorInfo)
        XCTAssertGreaterThan(parser.errorInfo?.line ?? 0, 0)
    }

    func testUnknownOption() throws {
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let m = Mappings()
        XCTAssertThrowsError(try parser.parse(mappings: m, content: ".unknown_option"))
        XCTAssertTrue(parser.errorInfo?.message.contains("Unknown option") ?? false)
    }

    // MARK: - Escape sequences in process names

    func testEscapedQuoteInProcessName() throws {
        let m = try parse("""
        cmd - a [
            "with \\"quotes\\"" : echo quoted
            * : echo default
        ]
        """)
        XCTAssertEqual(m.modeMap["default"]?.hotkeyMap.count, 1)
    }
}
