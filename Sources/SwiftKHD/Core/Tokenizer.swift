import Foundation

// MARK: - TokenType

public enum TokenType: Equatable {
    case identifier
    case activate       // ;mode_name (the mode name is the token text)
    case command        // text after ':'
    case modifier
    case literal        // named key like "return", "f1", "play"
    case keyHex         // 0x3C
    case key            // single char or digit key
    case decl           // ::
    case forward        // |
    case comma          // ,
    case insert         // <
    case plus           // +
    case dash           // -
    case arrow          // ->
    case capture        // @ (bare, in mode decl)
    case unbound        // ~
    case wildcard       // *
    case string         // "..."
    case option         // .keyword (text is the keyword without dot)
    case reference      // @name (text is name without @)
    case beginList      // [
    case endList        // ]
    case beginTuple     // (
    case endTuple       // )
    case unknown
}

// MARK: - Token

public struct Token {
    public let type: TokenType
    public let text: String
    public let line: Int
    public let column: Int

    public init(type: TokenType, text: String, line: Int, column: Int) {
        self.type = type
        self.text = text
        self.line = line
        self.column = column
    }
}

// MARK: - Tokenizer

public struct Tokenizer {
    private let buffer: [UInt8]
    private var pos: Int = 0
    private var line: Int = 1
    private var column: Int = 1

    private static let identifierChars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_".utf8)
    private static let identifierContinueChars = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789".utf8)
    private static let hexChars = Set("0123456789abcdefABCDEF".utf8)

    public init(buffer: String) {
        self.buffer = Array(buffer.utf8)
    }

    public mutating func nextToken() -> Token? {
        skipWhitespace()
        guard pos < buffer.count else { return nil }

        let tokenLine = line
        let tokenCol = column
        let ch = buffer[pos]

        switch ch {
        case UInt8(ascii: "+"):
            advance()
            return Token(type: .plus, text: "+", line: tokenLine, column: tokenCol)

        case UInt8(ascii: ","):
            advance()
            return Token(type: .comma, text: ",", line: tokenLine, column: tokenCol)

        case UInt8(ascii: "<"):
            advance()
            return Token(type: .insert, text: "<", line: tokenLine, column: tokenCol)

        case UInt8(ascii: "@"):
            advance()
            // If followed by identifier start, it's a reference
            if pos < buffer.count && Self.identifierChars.contains(buffer[pos]) {
                let name = acceptIdentifier()
                return Token(type: .reference, text: name, line: tokenLine, column: tokenCol)
            } else {
                return Token(type: .capture, text: "@", line: tokenLine, column: tokenCol)
            }

        case UInt8(ascii: "~"):
            advance()
            return Token(type: .unbound, text: "~", line: tokenLine, column: tokenCol)

        case UInt8(ascii: "*"):
            advance()
            return Token(type: .wildcard, text: "*", line: tokenLine, column: tokenCol)

        case UInt8(ascii: "["):
            advance()
            return Token(type: .beginList, text: "[", line: tokenLine, column: tokenCol)

        case UInt8(ascii: "]"):
            advance()
            return Token(type: .endList, text: "]", line: tokenLine, column: tokenCol)

        case UInt8(ascii: "("):
            advance()
            return Token(type: .beginTuple, text: "(", line: tokenLine, column: tokenCol)

        case UInt8(ascii: ")"):
            advance()
            return Token(type: .endTuple, text: ")", line: tokenLine, column: tokenCol)

        case UInt8(ascii: "."):
            advance()
            let name = acceptIdentifier()
            return Token(type: .option, text: name, line: tokenLine, column: tokenCol)

        case UInt8(ascii: "\""):
            advance()
            let str = acceptString()
            return Token(type: .string, text: str, line: tokenLine, column: tokenCol)

        case UInt8(ascii: "#"):
            // Comment — skip to end of line, then get next token
            skipUntil(UInt8(ascii: "\n"))
            return nextToken()

        case UInt8(ascii: "-"):
            advance()
            if pos < buffer.count && buffer[pos] == UInt8(ascii: ">") {
                advance()
                return Token(type: .arrow, text: "->", line: tokenLine, column: tokenCol)
            }
            return Token(type: .dash, text: "-", line: tokenLine, column: tokenCol)

        case UInt8(ascii: ";"):
            advance()
            skipWhitespace()
            let modLine = line
            let modCol = column
            let name = acceptIdentifier()
            return Token(type: .activate, text: name, line: modLine, column: modCol)

        case UInt8(ascii: ":"):
            advance()
            if pos < buffer.count && buffer[pos] == UInt8(ascii: ":") {
                advance()
                return Token(type: .decl, text: "::", line: tokenLine, column: tokenCol)
            }
            // Command token: skip whitespace, record position, read until newline
            skipWhitespace()
            let cmdLine = line
            let cmdCol = column
            // If next char is '@', emit empty command token (reference follows)
            if pos < buffer.count && buffer[pos] == UInt8(ascii: "@") {
                return Token(type: .command, text: "", line: cmdLine, column: cmdCol)
            }
            let cmd = acceptCommand()
            return Token(type: .command, text: cmd, line: cmdLine, column: cmdCol)

        case UInt8(ascii: "|"):
            advance()
            skipWhitespace()
            return Token(type: .forward, text: "|", line: tokenLine, column: tokenCol)

        default:
            // Hex literal: 0x...
            if ch == UInt8(ascii: "0") && pos + 1 < buffer.count && buffer[pos + 1] == UInt8(ascii: "x") {
                advance() // '0'
                advance() // 'x'
                let hex = acceptRun(Self.hexChars)
                return Token(type: .keyHex, text: hex, line: tokenLine, column: tokenCol)
            }

            // Digit key (single digit, not followed by more alphanumeric)
            if ch >= UInt8(ascii: "0") && ch <= UInt8(ascii: "9") {
                advance()
                let single = String(bytes: [ch], encoding: .utf8) ?? String(ch)
                return Token(type: .key, text: single, line: tokenLine, column: tokenCol)
            }

            // Alphabetic identifier
            if Self.identifierChars.contains(ch) {
                let start = pos
                _ = acceptRun(Self.identifierContinueChars)
                let text = String(bytes: Array(buffer[start..<pos]), encoding: .utf8) ?? ""
                let type_ = resolveIdentifierType(text)
                return Token(type: type_, text: text, line: tokenLine, column: tokenCol)
            }

            // Unknown
            advance()
            return Token(type: .unknown, text: String(bytes: [ch], encoding: .utf8) ?? "?",
                         line: tokenLine, column: tokenCol)
        }
    }

    // MARK: - Private helpers

    private mutating func advance() {
        guard pos < buffer.count else { return }
        if buffer[pos] == UInt8(ascii: "\n") {
            line += 1
            column = 1
        } else {
            column += 1
        }
        pos += 1
    }

    private mutating func skipWhitespace() {
        while pos < buffer.count {
            let ch = buffer[pos]
            if ch == UInt8(ascii: " ") || ch == UInt8(ascii: "\t") || ch == UInt8(ascii: "\n") || ch == UInt8(ascii: "\r") {
                advance()
            } else {
                break
            }
        }
    }

    @discardableResult
    private mutating func skipUntil(_ target: UInt8) {
        while pos < buffer.count && buffer[pos] != target {
            advance()
        }
    }

    private mutating func acceptRun(_ validSet: Set<UInt8>) -> String {
        let start = pos
        while pos < buffer.count && validSet.contains(buffer[pos]) {
            advance()
        }
        return String(bytes: Array(buffer[start..<pos]), encoding: .utf8) ?? ""
    }

    private mutating func acceptIdentifier() -> String {
        let start = pos
        // First: identifier_chars (alpha + underscore)
        while pos < buffer.count && Self.identifierChars.contains(buffer[pos]) {
            advance()
        }
        // Continue: identifier_chars + digits
        while pos < buffer.count && Self.identifierContinueChars.contains(buffer[pos]) {
            advance()
        }
        return String(bytes: Array(buffer[start..<pos]), encoding: .utf8) ?? ""
    }

    /// Accept a command: read until newline, handling backslash-newline continuation.
    private mutating func acceptCommand() -> String {
        var result: [UInt8] = []
        while pos < buffer.count {
            let ch = buffer[pos]
            if ch == UInt8(ascii: "\\") && pos + 1 < buffer.count && buffer[pos + 1] == UInt8(ascii: "\n") {
                // Line continuation: skip backslash and newline
                advance() // backslash
                advance() // newline
                continue
            }
            if ch == UInt8(ascii: "\n") {
                advance()
                break
            }
            result.append(ch)
            advance()
        }
        // Trim trailing whitespace (mirrors Zig's trimRight)
        while result.last == UInt8(ascii: " ") || result.last == UInt8(ascii: "\t") || result.last == UInt8(ascii: "\r") {
            result.removeLast()
        }
        return String(bytes: result, encoding: .utf8) ?? ""
    }

    /// Accept a quoted string (opening quote already consumed). Returns content without quotes.
    /// Handles escaped quotes: \" (odd number of preceding backslashes = escaped).
    private mutating func acceptString() -> String {
        let start = pos
        var result: [UInt8] = []
        while pos < buffer.count {
            let ch = buffer[pos]
            if ch == UInt8(ascii: "\"") {
                // Count preceding backslashes in result
                var backslashCount = 0
                var checkIdx = result.count - 1
                while checkIdx >= 0 && result[checkIdx] == UInt8(ascii: "\\") {
                    backslashCount += 1
                    checkIdx -= 1
                }
                if backslashCount % 2 == 1 {
                    // Escaped quote: include it and continue
                    result.append(ch)
                    advance()
                    continue
                }
                // Closing quote
                advance()
                break
            }
            result.append(ch)
            advance()
        }
        _ = start // suppress warning
        return String(bytes: result, encoding: .utf8) ?? ""
    }

    private func resolveIdentifierType(_ text: String) -> TokenType {
        if text.count == 1 {
            return .key
        }
        if ModifierFlag.named(text) != nil {
            return .modifier
        }
        if literalKeycodeStr.contains(text) {
            return .literal
        }
        return .identifier
    }
}
