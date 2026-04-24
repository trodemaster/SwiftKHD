import Foundation

public struct ParseError: Error, CustomStringConvertible {
    public let message: String
    public let line: Int
    public let column: Int
    public let filePath: String?

    public init(message: String, line: Int, column: Int, filePath: String? = nil) {
        self.message = message
        self.line = line
        self.column = column
        self.filePath = filePath
    }

    public var description: String {
        let loc = filePath.map { "\($0):\(line):\(column)" } ?? "\(line):\(column)"
        return "\(loc): error: \(message)"
    }
}
