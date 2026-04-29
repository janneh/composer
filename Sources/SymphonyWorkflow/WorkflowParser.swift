import Foundation

public struct WorkflowFrontMatter: Hashable, Sendable {
    public var fields: [String: WorkflowFrontMatterValue]

    public init(fields: [String: WorkflowFrontMatterValue] = [:]) {
        self.fields = fields
    }

    public subscript(_ key: String) -> WorkflowFrontMatterValue? {
        fields[key]
    }

    public func string(for key: String) -> String? {
        fields[key]?.stringValue
    }

    public func bool(for key: String) -> Bool? {
        fields[key]?.boolValue
    }

    public func stringList(for key: String) -> [String]? {
        fields[key]?.stringListValue
    }
}

public enum WorkflowFrontMatterValue: Hashable, Sendable {
    case string(String)
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case stringList([String])

    public var stringValue: String? {
        if case let .string(value) = self {
            return value
        }
        return nil
    }

    public var boolValue: Bool? {
        if case let .bool(value) = self {
            return value
        }
        return nil
    }

    public var stringListValue: [String]? {
        if case let .stringList(value) = self {
            return value
        }
        return nil
    }
}

public enum WorkflowParser {
    public static func parse(content: String, fileURL: URL) throws -> WorkflowDocument {
        let normalizedContent = content.normalizedLineEndings
        let lines = normalizedContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else {
            return WorkflowDocument(fileURL: fileURL, content: content, frontMatter: nil, body: content)
        }

        guard let closingIndex = lines.dropFirst().firstIndex(where: { line in
            line.trimmingCharacters(in: .whitespacesAndNewlines) == "---"
        }) else {
            throw WorkflowParserError.unclosedFrontMatter(fileURL: fileURL)
        }

        let frontMatterLines = Array(lines[1..<closingIndex])
        let body = Array(lines.dropFirst(closingIndex + 1)).joined(separator: "\n")
        let frontMatter = try parseFrontMatter(lines: frontMatterLines, fileURL: fileURL)
        return WorkflowDocument(
            fileURL: fileURL,
            content: content,
            frontMatter: frontMatter,
            body: body
        )
    }

    private static func parseFrontMatter(lines: [String], fileURL: URL) throws -> WorkflowFrontMatter {
        var fields: [String: WorkflowFrontMatterValue] = [:]

        for (offset, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else {
                continue
            }

            guard let colonIndex = line.firstIndex(of: ":") else {
                throw WorkflowParserError.invalidFrontMatterLine(
                    fileURL: fileURL,
                    line: offset + 2,
                    reason: "Expected key: value."
                )
            }

            let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawValue = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard isValidKey(key) else {
                throw WorkflowParserError.invalidFrontMatterLine(
                    fileURL: fileURL,
                    line: offset + 2,
                    reason: "Invalid key '\(key)'."
                )
            }

            fields[key] = try parseValue(rawValue, fileURL: fileURL, line: offset + 2)
        }

        return WorkflowFrontMatter(fields: fields)
    }

    private static func parseValue(_ rawValue: String, fileURL: URL, line: Int) throws -> WorkflowFrontMatterValue {
        if rawValue.hasPrefix("[") || rawValue.hasSuffix("]") {
            return .stringList(try parseStringList(rawValue, fileURL: fileURL, line: line))
        }

        if let quoted = parseQuotedString(rawValue) {
            return .string(quoted)
        }

        switch rawValue.lowercased() {
        case "true":
            return .bool(true)
        case "false":
            return .bool(false)
        default:
            break
        }

        if let integer = Int(rawValue) {
            return .integer(integer)
        }

        if let number = Double(rawValue), rawValue.contains(".") {
            return .number(number)
        }

        return .string(rawValue)
    }

    private static func parseStringList(_ rawValue: String, fileURL: URL, line: Int) throws -> [String] {
        guard rawValue.hasPrefix("["), rawValue.hasSuffix("]") else {
            throw WorkflowParserError.invalidFrontMatterLine(
                fileURL: fileURL,
                line: line,
                reason: "Invalid inline string list."
            )
        }

        let inner = rawValue.dropFirst().dropLast()
        guard !inner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return try splitListItems(String(inner), fileURL: fileURL, line: line).map { item in
            parseQuotedString(item) ?? item.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func splitListItems(_ value: String, fileURL: URL, line: Int) throws -> [String] {
        var items: [String] = []
        var current = ""
        var quote: Character?

        for character in value {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }

            if character == ",", quote == nil {
                items.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        guard quote == nil else {
            throw WorkflowParserError.invalidFrontMatterLine(
                fileURL: fileURL,
                line: line,
                reason: "Unclosed quoted string in list."
            )
        }

        items.append(current)
        return items.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func parseQuotedString(_ value: String) -> String? {
        guard value.count >= 2, let first = value.first, let last = value.last else {
            return nil
        }

        guard (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return nil
        }

        return String(value.dropFirst().dropLast())
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.first, first.isLetter else {
            return false
        }

        return key.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_" || character == "-" || character == "."
        }
    }
}

public enum WorkflowParserError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case unclosedFrontMatter(fileURL: URL)
    case invalidFrontMatterLine(fileURL: URL, line: Int, reason: String)

    public var description: String {
        switch self {
        case let .unclosedFrontMatter(fileURL):
            return "Unclosed workflow front matter in \(fileURL.path)."
        case let .invalidFrontMatterLine(fileURL, line, reason):
            return "Invalid workflow front matter in \(fileURL.path) on line \(line): \(reason)"
        }
    }

    public var errorDescription: String? {
        description
    }
}

private extension String {
    var normalizedLineEndings: String {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
