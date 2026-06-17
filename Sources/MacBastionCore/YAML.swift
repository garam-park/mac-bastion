import Foundation

public enum YAMLValue: Equatable {
    case map([String: YAMLValue])
    case array([YAMLValue])
    case string(String)
    case int(Int)
    case bool(Bool)
    case null
}

public final class YAMLParser {
    private struct Line {
        let number: Int
        let indent: Int
        let content: String
    }

    private var lines: [Line] = []
    private var index: Int = 0

    public init() {}

    public func parse(_ text: String) throws -> YAMLValue {
        lines = Self.normalizedLines(from: text)
        index = 0

        guard let first = lines.first else {
            return .map([:])
        }

        let value = try parseBlock(indent: first.indent)
        if index < lines.count {
            throw MacBastionError.parse("Unexpected content at line \(lines[index].number)")
        }
        return value
    }

    private func parseBlock(indent: Int) throws -> YAMLValue {
        guard index < lines.count else {
            return .null
        }

        let line = lines[index]
        if line.indent < indent {
            return .null
        }
        if line.content.hasPrefix("- ") {
            return try parseArray(indent: line.indent)
        }
        return try parseMap(indent: line.indent)
    }

    private func parseMap(indent: Int) throws -> YAMLValue {
        var result: [String: YAMLValue] = [:]

        while index < lines.count {
            let line = lines[index]
            if line.indent < indent {
                break
            }
            if line.indent > indent {
                throw MacBastionError.parse("Unexpected indentation at line \(line.number)")
            }
            if line.content.hasPrefix("- ") {
                break
            }

            let pair = try splitKeyValue(line.content, lineNumber: line.number)
            index += 1

            if pair.value.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    result[pair.key] = try parseBlock(indent: lines[index].indent)
                } else {
                    result[pair.key] = .null
                }
            } else {
                result[pair.key] = try parseScalar(pair.value, lineNumber: line.number)
            }
        }

        return .map(result)
    }

    private func parseArray(indent: Int) throws -> YAMLValue {
        var result: [YAMLValue] = []

        while index < lines.count {
            let line = lines[index]
            if line.indent < indent {
                break
            }
            if line.indent > indent {
                throw MacBastionError.parse("Unexpected indentation at line \(line.number)")
            }
            guard line.content.hasPrefix("- ") else {
                break
            }

            let itemText = String(line.content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            index += 1

            if itemText.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    result.append(try parseBlock(indent: lines[index].indent))
                } else {
                    result.append(.null)
                }
                continue
            }

            if let pair = try optionalKeyValue(itemText, lineNumber: line.number) {
                var itemMap: [String: YAMLValue] = [:]
                itemMap[pair.key] = try valueForPair(pair, parentIndent: indent, lineNumber: line.number)

                let childIndent = indent + 2
                while index < lines.count {
                    let next = lines[index]
                    if next.indent <= indent {
                        break
                    }
                    if next.indent != childIndent {
                        throw MacBastionError.parse("Expected indentation \(childIndent) at line \(next.number)")
                    }
                    if next.content.hasPrefix("- ") {
                        break
                    }

                    let nextPair = try splitKeyValue(next.content, lineNumber: next.number)
                    index += 1
                    itemMap[nextPair.key] = try valueForPair(nextPair, parentIndent: childIndent, lineNumber: next.number)
                }

                result.append(.map(itemMap))
            } else {
                result.append(try parseScalar(itemText, lineNumber: line.number))
            }
        }

        return .array(result)
    }

    private func valueForPair(
        _ pair: (key: String, value: String),
        parentIndent: Int,
        lineNumber: Int
    ) throws -> YAMLValue {
        if pair.value.isEmpty {
            if index < lines.count, lines[index].indent > parentIndent {
                return try parseBlock(indent: lines[index].indent)
            }
            return .null
        }
        return try parseScalar(pair.value, lineNumber: lineNumber)
    }

    private func splitKeyValue(
        _ content: String,
        lineNumber: Int
    ) throws -> (key: String, value: String) {
        guard let colonIndex = firstUnquotedColon(in: content) else {
            throw MacBastionError.parse("Expected key/value at line \(lineNumber)")
        }
        let key = String(content[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else {
            throw MacBastionError.parse("Empty key at line \(lineNumber)")
        }
        let valueStart = content.index(after: colonIndex)
        let value = String(content[valueStart...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private func optionalKeyValue(
        _ content: String,
        lineNumber: Int
    ) throws -> (key: String, value: String)? {
        guard let colonIndex = firstUnquotedColon(in: content) else {
            return nil
        }

        let key = String(content[..<colonIndex]).trimmingCharacters(in: .whitespaces)
        guard isPlainKey(key) else {
            return nil
        }

        let valueStart = content.index(after: colonIndex)
        let value = String(content[valueStart...]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private func parseScalar(_ raw: String, lineNumber: Int) throws -> YAMLValue {
        let value = raw.trimmingCharacters(in: .whitespaces)
        if value.isEmpty || value == "null" || value == "~" {
            return .null
        }
        if value == "true" {
            return .bool(true)
        }
        if value == "false" {
            return .bool(false)
        }
        if value.hasPrefix("[") && value.hasSuffix("]") {
            return .array(try parseInlineArray(value, lineNumber: lineNumber))
        }
        if let int = Int(value) {
            return .int(int)
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'")) {
            return .string(unquote(value))
        }
        return .string(value)
    }

    private func parseInlineArray(_ raw: String, lineNumber: Int) throws -> [YAMLValue] {
        let body = raw.dropFirst().dropLast()
        var values: [YAMLValue] = []
        var current = ""
        var quote: Character?

        for character in body {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                current.append(character)
                continue
            }

            if character == ",", quote == nil {
                let part = current.trimmingCharacters(in: .whitespaces)
                if !part.isEmpty {
                    values.append(try parseScalar(part, lineNumber: lineNumber))
                }
                current = ""
            } else {
                current.append(character)
            }
        }

        if quote != nil {
            throw MacBastionError.parse("Unterminated quote in inline array at line \(lineNumber)")
        }

        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty {
            values.append(try parseScalar(tail, lineNumber: lineNumber))
        }
        return values
    }

    private func firstUnquotedColon(in content: String) -> String.Index? {
        var quote: Character?
        var previous: Character?

        for index in content.indices {
            let character = content[index]
            if character == "\"" || character == "'" {
                if quote == character, previous != "\\" {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }
            if character == ":", quote == nil {
                return index
            }
            previous = character
        }
        return nil
    }

    private func isPlainKey(_ key: String) -> Bool {
        guard !key.isEmpty else {
            return false
        }
        return key.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_" || character == "-" || character == "."
        }
    }

    private func unquote(_ raw: String) -> String {
        let first = raw.first
        let inner = raw.dropFirst().dropLast()
        if first == "'" {
            return inner.replacingOccurrences(of: "''", with: "'")
        }
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\n", with: "\n")
    }

    private static func normalizedLines(from text: String) -> [Line] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, rawLine in
                let noComment = stripComment(String(rawLine))
                guard !noComment.trimmingCharacters(in: .whitespaces).isEmpty else {
                    return nil
                }
                let indent = noComment.prefix { $0 == " " }.count
                let content = noComment.trimmingCharacters(in: .whitespaces)
                return Line(number: offset + 1, indent: indent, content: content)
            }
    }

    private static func stripComment(_ line: String) -> String {
        var quote: Character?
        var previous: Character?

        for index in line.indices {
            let character = line[index]
            if character == "\"" || character == "'" {
                if quote == character, previous != "\\" {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
            }
            if character == "#", quote == nil {
                if index == line.startIndex || line[line.index(before: index)].isWhitespace {
                    return String(line[..<index])
                }
            }
            previous = character
        }
        return line
    }
}
