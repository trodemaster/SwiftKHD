import XCTest
@testable import SwiftKHD

final class HotkeyTests: XCTestCase {

    // MARK: - ModifierFlag

    func testModifierFlagBasicOptions() {
        let flags: ModifierFlag = [.cmd, .shift]
        XCTAssertTrue(flags.contains(.cmd))
        XCTAssertTrue(flags.contains(.shift))
        XCTAssertFalse(flags.contains(.alt))
    }

    func testModifierFlagLRDistinction() {
        XCTAssertNotEqual(ModifierFlag.lcmd, ModifierFlag.rcmd)
        XCTAssertNotEqual(ModifierFlag.lalt, ModifierFlag.ralt)
        XCTAssertNotEqual(ModifierFlag.lshift, ModifierFlag.rshift)
        XCTAssertNotEqual(ModifierFlag.lcontrol, ModifierFlag.rcontrol)
    }

    func testModifierFlagNamed() {
        XCTAssertEqual(ModifierFlag.named("cmd"), .cmd)
        XCTAssertEqual(ModifierFlag.named("lcmd"), .lcmd)
        XCTAssertEqual(ModifierFlag.named("hyper"), .hyper)
        XCTAssertEqual(ModifierFlag.named("meh"), .meh)
        XCTAssertNil(ModifierFlag.named("unknown"))
    }

    func testHyperMeh() {
        XCTAssertTrue(ModifierFlag.hyper.contains(.cmd))
        XCTAssertTrue(ModifierFlag.hyper.contains(.alt))
        XCTAssertTrue(ModifierFlag.hyper.contains(.shift))
        XCTAssertTrue(ModifierFlag.hyper.contains(.control))
        XCTAssertFalse(ModifierFlag.meh.contains(.cmd))
    }

    // MARK: - hotkeyFlagsMatch

    func testGeneralModMatchesSpecific() {
        // Config has general .cmd, keyboard has .lcmd — should match
        XCTAssertTrue(hotkeyFlagsMatch(config: [.cmd], keyboard: [.lcmd]))
        XCTAssertTrue(hotkeyFlagsMatch(config: [.cmd], keyboard: [.rcmd]))
        XCTAssertTrue(hotkeyFlagsMatch(config: [.cmd], keyboard: [.cmd]))

        XCTAssertTrue(hotkeyFlagsMatch(config: [.alt], keyboard: [.lalt]))
        XCTAssertTrue(hotkeyFlagsMatch(config: [.alt], keyboard: [.ralt]))

        XCTAssertTrue(hotkeyFlagsMatch(config: [.shift], keyboard: [.lshift]))
        XCTAssertTrue(hotkeyFlagsMatch(config: [.control], keyboard: [.lcontrol]))
    }

    func testSpecificModDoesNotMatchGeneral() {
        // Config has .lcmd, keyboard has .cmd — should NOT match
        XCTAssertFalse(hotkeyFlagsMatch(config: [.lcmd], keyboard: [.cmd]))
        XCTAssertFalse(hotkeyFlagsMatch(config: [.lalt], keyboard: [.alt]))
        XCTAssertFalse(hotkeyFlagsMatch(config: [.lcmd], keyboard: [.rcmd]))
    }

    func testExactSpecificMatch() {
        // Config .lcmd, keyboard .lcmd — exact match
        XCTAssertTrue(hotkeyFlagsMatch(config: [.lcmd], keyboard: [.lcmd]))
        XCTAssertFalse(hotkeyFlagsMatch(config: [.lcmd], keyboard: [.rcmd]))
    }

    func testFnNxExactMatch() {
        XCTAssertTrue(hotkeyFlagsMatch(config: [.fn_], keyboard: [.fn_]))
        XCTAssertFalse(hotkeyFlagsMatch(config: [.fn_], keyboard: []))
        XCTAssertTrue(hotkeyFlagsMatch(config: [.nx], keyboard: [.nx]))
    }

    func testNoFlagsMatch() {
        XCTAssertTrue(hotkeyFlagsMatch(config: [], keyboard: []))
        XCTAssertFalse(hotkeyFlagsMatch(config: [], keyboard: [.cmd]))
    }

    // MARK: - HotkeyMap

    func testHotkeyMapInsertAndLookup() throws {
        let map = HotkeyMap()
        let h = Hotkey(flags: [.cmd], key: 0x00)
        try map.insert(h)
        let found = map.lookup(keyPress: KeyPress(flags: [.cmd], key: 0x00))
        XCTAssertNotNil(found)
    }

    func testHotkeyMapGeneralModLookup() throws {
        let map = HotkeyMap()
        let h = Hotkey(flags: [.cmd], key: 0x00)
        try map.insert(h)
        // Keyboard sends lcmd — should match config cmd
        let found = map.lookup(keyPress: KeyPress(flags: [.lcmd], key: 0x00))
        XCTAssertNotNil(found)
    }

    func testHotkeyMapDuplicateThrows() throws {
        let map = HotkeyMap()
        let h1 = Hotkey(flags: [.cmd], key: 0x00)
        let h2 = Hotkey(flags: [.cmd], key: 0x00)
        try map.insert(h1)
        XCTAssertThrowsError(try map.insert(h2)) { error in
            XCTAssertEqual(error as? HotkeyError, .duplicateHotkeyInMode)
        }
    }

    func testHotkeyMapDifferentModifiersAllowed() throws {
        let map = HotkeyMap()
        let h1 = Hotkey(flags: [.lcmd], key: 0x00)
        let h2 = Hotkey(flags: [.rcmd], key: 0x00)
        try map.insert(h1)
        XCTAssertNoThrow(try map.insert(h2))
        XCTAssertEqual(map.count, 2)
    }

    // MARK: - ProcessCommand lookup

    func testFindCommandForProcess() {
        let h = Hotkey()
        try? h.addProcessCommand("terminal", command: "echo terminal")
        try? h.addProcessCommand("*", command: "echo default")
        XCTAssertEqual(
            { () -> String? in if case .command(let c) = h.findCommandForProcess("terminal") { return c } else { return nil } }(),
            "echo terminal"
        )
        XCTAssertEqual(
            { () -> String? in if case .command(let c) = h.findCommandForProcess("safari") { return c } else { return nil } }(),
            "echo default"
        )
    }

    func testFindCommandCaseInsensitive() {
        let h = Hotkey()
        try? h.addProcessCommand("Terminal", command: "echo t")
        XCTAssertNotNil(h.findCommandForProcess("terminal"))
        XCTAssertNotNil(h.findCommandForProcess("TERMINAL"))
    }

    func testDuplicateProcessCommandThrows() {
        let h = Hotkey()
        try? h.addProcessCommand("terminal", command: "echo t")
        XCTAssertThrowsError(try h.addProcessCommand("terminal", command: "echo other"))
    }

    func testWildcardCommandAlreadyExistsThrows() {
        let h = Hotkey()
        try? h.addProcessCommand("*", command: "echo default")
        XCTAssertThrowsError(try h.addProcessCommand("*", command: "echo other"))
    }

    func testUnboundAction() {
        let h = Hotkey()
        try? h.addProcessUnbound("*")
        if case .unbound = h.findCommandForProcess("any") { } else {
            XCTFail("Expected unbound")
        }
    }

    func testForwardedAction() {
        let h = Hotkey()
        let target = KeyPress(flags: [.cmd], key: 0x7B) // cmd - left
        try? h.addProcessForward("*", keyPress: target)
        if case .forwarded(let kp) = h.findCommandForProcess("any") {
            XCTAssertEqual(kp.key, 0x7B)
        } else {
            XCTFail("Expected forwarded")
        }
    }

    func testActivationAction() {
        let h = Hotkey()
        try? h.addProcessActivation("*", modeName: "window", command: "echo activated")
        if case .activation(let name, let cmd) = h.findCommandForProcess("any") {
            XCTAssertEqual(name, "window")
            XCTAssertEqual(cmd, "echo activated")
        } else {
            XCTFail("Expected activation")
        }
    }
}
