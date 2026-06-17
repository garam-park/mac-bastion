import Foundation

public enum MacBastionError: Error, CustomStringConvertible, LocalizedError {
    case message(String)
    case fileNotFound(String)
    case parse(String)
    case validationFailed([ValidationIssue])

    public var description: String {
        switch self {
        case let .message(message):
            return message
        case let .fileNotFound(path):
            return "File not found: \(path)"
        case let .parse(message):
            return "Parse error: \(message)"
        case let .validationFailed(issues):
            let errors = issues.filter { $0.severity == .error }
            return "Validation failed with \(errors.count) error(s)"
        }
    }

    public var errorDescription: String? {
        description
    }
}
