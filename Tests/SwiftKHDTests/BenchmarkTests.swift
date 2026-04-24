import XCTest
@testable import SwiftKHD

final class BenchmarkTests: XCTestCase {

    // MARK: - Hotkey lookup performance

    func testHotkeyLookupPerformance() throws {
        let map = HotkeyMap()
        // Insert 50 hotkeys with distinct (flags, key) pairs
        for i in 0..<50 {
            let h = Hotkey(flags: [.cmd], key: UInt32(i))
            try map.insert(h)
        }
        let target = KeyPress(flags: [.lcmd], key: 25) // matches .cmd - key25

        measure {
            for _ in 0..<10_000 {
                _ = map.lookup(keyPress: target)
            }
        }
    }

    // MARK: - Config parse performance

    func testConfigParsePerformance() throws {
        let content = (0..<50).map { "cmd - 0x\(String($0, radix: 16)) : echo hello \($0)" }.joined(separator: "\n")
        let keycodes = try Keycodes()

        measure {
            let parser = Parser(keycodes: keycodes)
            let mappings = Mappings()
            _ = try? parser.parse(mappings: mappings, content: content)
        }
    }

    // MARK: - hotkeyFlagsMatch performance

    func testFlagsMatchPerformance() {
        let config: ModifierFlag = [.cmd]
        let keyboard: ModifierFlag = [.lcmd]

        measure {
            for _ in 0..<1_000_000 {
                _ = hotkeyFlagsMatch(config: config, keyboard: keyboard)
            }
        }
    }

    // MARK: - Tokenizer performance

    func testTokenizerPerformance() throws {
        let content = String(repeating: "cmd - a : echo hello\n", count: 100)

        measure {
            var tok = Tokenizer(buffer: content)
            while tok.nextToken() != nil {}
        }
    }
}
