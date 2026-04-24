import XCTest
@testable import SwiftKHD

final class MappingsTests: XCTestCase {

    func testDefaultModeExists() {
        let m = Mappings()
        XCTAssertNotNil(m.modeMap["default"])
    }

    func testShellDefault() {
        let m = Mappings()
        XCTAssertFalse(m.shell.isEmpty)
    }

    func testSetShell() {
        let m = Mappings()
        m.setShell("/bin/zsh")
        XCTAssertEqual(m.shell, "/bin/zsh")
    }

    func testBlacklist() {
        let m = Mappings()
        m.addBlacklist("loginwindow")
        XCTAssertTrue(m.isBlacklisted("loginwindow"))
        XCTAssertTrue(m.isBlacklisted("LOGINWINDOW")) // case insensitive
        XCTAssertFalse(m.isBlacklisted("terminal"))
    }

    func testPutMode() {
        let m = Mappings()
        let mode = Mode(name: "window")
        m.putMode(mode)
        XCTAssertNotNil(m.modeMap["window"])
    }

    func testGetOrCreateDefaultExists() {
        let m = Mappings()
        let d = m.getOrCreateDefault("default")
        XCTAssertNotNil(d)
        XCTAssertEqual(d?.name, "default")
    }

    func testGetOrCreateDefaultUndeclaredReturnsNil() {
        let m = Mappings()
        // Undeclared non-default mode returns nil
        let result = m.getOrCreateMode("undeclared")
        XCTAssertNil(result)
    }

    func testLoadedFilesEmpty() {
        let m = Mappings()
        XCTAssertTrue(m.loadedFiles.isEmpty)
    }
}
