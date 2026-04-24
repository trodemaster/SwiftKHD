import XCTest
@testable import SwiftKHD

/// Parses all testdata/ config files from skhd.zig and verifies they parse without error.
final class ConfigRoundtripTests: XCTestCase {

    private func resourceURL(_ filename: String) -> URL? {
        Bundle.module.url(forResource: filename, withExtension: nil, subdirectory: "testdata")
    }

    private func parse(_ filename: String) throws -> Mappings {
        guard let url = resourceURL(filename) else {
            throw XCTestError(.failureWhileWaiting, userInfo: ["msg": "Test resource not found: \(filename)"])
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let keycodes = try Keycodes()
        let parser = Parser(keycodes: keycodes)
        let mappings = Mappings()
        try parser.parseWithPath(mappings: mappings, content: content,
                                 filePath: url.path)
        try parser.processLoadDirectives(mappings: mappings)
        return mappings
    }

    func testBasicSkhdrc() throws {
        let m = try parse("test-skhdrc")
        XCTAssertFalse(m.modeMap.isEmpty)
    }

    func testProcessGroups() throws {
        let m = try parse("example_process_groups.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testLRModifiers() throws {
        let m = try parse("test-lr-modifiers.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testModifierMatching() throws {
        let m = try parse("test_modifier_matching.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testMediaKeyForward() throws {
        let m = try parse("test_media_key_forward.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testHomeKey() throws {
        let m = try parse("test_home_key.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testShellSkhdrc() throws {
        let m = try parse("test-shell.skhdrc")
        XCTAssertFalse(m.shell.isEmpty)
    }

    func testProcessSkhdrc() throws {
        let m = try parse("test-process.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testForwardSkhdrc() throws {
        let m = try parse("test-forward.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testDebugMatch() throws {
        let m = try parse("test_debug_match.skhdrc")
        XCTAssertFalse(m.modeMap["default"]?.hotkeyMap.count == 0)
    }

    func testParseErrorsFileContainsErrors() {
        // parse_errors.skhdrc is intentionally invalid — verify it does fail
        XCTAssertThrowsError(try parse("parse_errors.skhdrc"))
    }
}
