import XCTest
@testable import SwiftKHD

final class TokenizerTests: XCTestCase {

    private func tokens(_ input: String) -> [Token] {
        var tok = Tokenizer(buffer: input)
        var result: [Token] = []
        while let t = tok.nextToken() { result.append(t) }
        return result
    }

    func testSimpleHotkey() {
        let toks = tokens("cmd - a : echo test")
        XCTAssertEqual(toks[0].type, .modifier); XCTAssertEqual(toks[0].text, "cmd")
        XCTAssertEqual(toks[1].type, .dash)
        XCTAssertEqual(toks[2].type, .key);      XCTAssertEqual(toks[2].text, "a")
        XCTAssertEqual(toks[3].type, .command);  XCTAssertEqual(toks[3].text, "echo test")
    }

    func testCommentSkipping() {
        let toks = tokens("# comment\ncmd - a : echo")
        XCTAssertEqual(toks[0].type, .modifier)
        XCTAssertEqual(toks[0].text, "cmd")
    }

    func testOptionToken() {
        let toks = tokens(".shell \"/bin/zsh\"")
        XCTAssertEqual(toks[0].type, .option);  XCTAssertEqual(toks[0].text, "shell")
        XCTAssertEqual(toks[1].type, .string);  XCTAssertEqual(toks[1].text, "/bin/zsh")
    }

    func testHexKey() {
        let toks = tokens("0x3C")
        XCTAssertEqual(toks[0].type, .keyHex)
        XCTAssertEqual(toks[0].text, "3C")
    }

    func testReference() {
        let toks = tokens("@yabai_focus(\"west\")")
        XCTAssertEqual(toks[0].type, .reference);   XCTAssertEqual(toks[0].text, "yabai_focus")
        XCTAssertEqual(toks[1].type, .beginTuple)
        XCTAssertEqual(toks[2].type, .string);      XCTAssertEqual(toks[2].text, "west")
        XCTAssertEqual(toks[3].type, .endTuple)
    }

    func testCaptureVsReference() {
        // Bare @ is capture
        let captureToks = tokens(":: mode @")
        let captureToken = captureToks.first { $0.type == .capture }
        XCTAssertNotNil(captureToken)

        // @name is reference
        let refToks = tokens("@name")
        XCTAssertEqual(refToks[0].type, .reference)
    }

    func testModeDecl() {
        let toks = tokens(":: window @ : echo entered")
        XCTAssertEqual(toks[0].type, .decl)
        XCTAssertEqual(toks[1].type, .identifier); XCTAssertEqual(toks[1].text, "window")
        XCTAssertEqual(toks[2].type, .capture)
        XCTAssertEqual(toks[3].type, .command)
    }

    func testArrow() {
        let toks = tokens("cmd - p -> : echo")
        XCTAssertTrue(toks.contains { $0.type == .arrow })
    }

    func testForward() {
        let toks = tokens("cmd - h | left")
        XCTAssertTrue(toks.contains { $0.type == .forward })
    }

    func testUnbound() {
        let toks = tokens("cmd - a ~")
        XCTAssertTrue(toks.contains { $0.type == .unbound })
    }

    func testStringWithEscapedQuote() {
        let toks = tokens("\"with \\\"quotes\\\"\"")
        XCTAssertEqual(toks[0].type, .string)
        XCTAssertEqual(toks[0].text, "with \\\"quotes\\\"")
    }

    func testCommandContinuation() {
        let toks = tokens(": echo hello \\\n   world")
        XCTAssertEqual(toks[0].type, .command)
        XCTAssertTrue(toks[0].text.contains("hello"))
        XCTAssertTrue(toks[0].text.contains("world"))
    }

    func testEmptyCommandBeforeReference() {
        let toks = tokens(": @toggle(\"Firefox\")")
        XCTAssertEqual(toks[0].type, .command); XCTAssertEqual(toks[0].text, "")
        XCTAssertEqual(toks[1].type, .reference)
    }

    func testModifiers() {
        for mod in ["cmd", "alt", "shift", "ctrl", "fn", "lcmd", "rcmd", "lalt", "ralt",
                    "lshift", "rshift", "lctrl", "rctrl", "hyper", "meh"] {
            let toks = tokens(mod)
            XCTAssertEqual(toks[0].type, .modifier, "Expected \(mod) to be a modifier")
        }
    }

    func testLiteralKeys() {
        for lit in ["return", "tab", "space", "escape", "f1", "play", "sound_up"] {
            let toks = tokens(lit)
            XCTAssertEqual(toks[0].type, .literal, "Expected \(lit) to be a literal key")
        }
    }

    func testActivate() {
        let toks = tokens("; window")
        XCTAssertEqual(toks[0].type, .activate)
        XCTAssertEqual(toks[0].text, "window")
    }

    func testWildcard() {
        let toks = tokens("*")
        XCTAssertEqual(toks[0].type, .wildcard)
    }

    func testLineNumbers() {
        let toks = tokens("cmd - a : echo\ncmd - b : echo")
        XCTAssertEqual(toks[0].line, 1)
        // second hotkey starts on line 2
        let secondCmd = toks.first { $0.type == .modifier && $0.text == "cmd" && $0.line == 2 }
        XCTAssertNotNil(secondCmd)
    }
}
