import XCTest
@testable import SwiftKHD

final class KeycodesTests: XCTestCase {

    func testInit() throws {
        XCTAssertNoThrow(try Keycodes())
    }

    func testLiteralTableLength() {
        XCTAssertEqual(literalKeycodeStr.count, literalKeycodeValue.count)
    }

    func testLiteralTableBoundaries() {
        // index 4 (escape) is the boundary; keys with index > 4 and < 35 get fn mod
        XCTAssertEqual(literalKeycodeStr[keyHasImplicitFnMod], "escape")
        // first fn-mod key is "backtick" at index 5, then "delete" at index 6
        XCTAssertEqual(literalKeycodeStr[keyHasImplicitFnMod + 2], "delete")
        // index 35 (f20) is the nx-mod boundary — i >= 35 gets nx mod
        XCTAssertEqual(literalKeycodeStr[keyHasImplicitNxMod], "f20")
        XCTAssertEqual(literalKeycodeStr[keyHasImplicitNxMod + 1], "sound_up")
    }

    func testCommonKeyResolution() throws {
        let keycodes = try Keycodes()
        // 'a' should resolve to kVK_ANSI_A (0x00)
        let aCode = try keycodes.getKeycode("a")
        XCTAssertEqual(aCode, 0x00) // kVK_ANSI_A
    }

    func testUnknownKeyThrows() throws {
        let keycodes = try Keycodes()
        XCTAssertThrowsError(try keycodes.getKeycode("nonexistent_key_xyz")) { error in
            if case KeycodesError.keyNotFound = error { } else {
                XCTFail("Expected keyNotFound")
            }
        }
    }

    func testFnModBoundary() {
        // key at index 5 (backtick) has no fn mod; key at index 6 (delete) has fn mod
        XCTAssertEqual(literalKeycodeStr[5], "backtick")
        XCTAssertEqual(literalKeycodeStr[6], "delete")
    }

    func testMediaKeyValues() {
        // Sound up should be at NX index (sound_up = first NX key)
        let idx = literalKeycodeStr.firstIndex(of: "sound_up")!
        XCTAssertGreaterThanOrEqual(idx, keyHasImplicitNxMod)
        XCTAssertEqual(literalKeycodeValue[idx], 0) // NX_KEYTYPE_SOUND_UP = 0
    }
}
