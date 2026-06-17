import Darwin
import Foundation

public enum ValidationSeverity: String, Comparable {
    case info
    case warning
    case error

    public static func < (lhs: ValidationSeverity, rhs: ValidationSeverity) -> Bool {
        order(lhs) < order(rhs)
    }

    private static func order(_ severity: ValidationSeverity) -> Int {
        switch severity {
        case .info:
            return 0
        case .warning:
            return 1
        case .error:
            return 2
        }
    }
}

public struct ValidationIssue: Equatable, CustomStringConvertible {
    public var severity: ValidationSeverity
    public var code: String
    public var message: String
    public var profileName: String?

    public init(
        severity: ValidationSeverity,
        code: String,
        message: String,
        profileName: String? = nil
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.profileName = profileName
    }

    public var description: String {
        let profile = profileName.map { " [\($0)]" } ?? ""
        return "\(severity.rawValue.uppercased()) \(code)\(profile): \(message)"
    }
}

public enum ConfigValidator {
    public static func validate(_ config: BastionConfig, checkLivePorts: Bool = false) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        var profileNames: [String: Int] = [:]
        var localPorts: [ForwardEndpoint: [String]] = [:]

        if config.apiVersion != "mac-bastion/v1" {
            issues.append(ValidationIssue(
                severity: .warning,
                code: "config.version",
                message: "Unknown apiVersion '\(config.apiVersion)'. Supported version is mac-bastion/v1."
            ))
        }

        for profile in config.profiles {
            if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    code: "profile.name.empty",
                    message: "Profile name is required."
                ))
            }
            profileNames[profile.name, default: 0] += 1

            if profile.bastion.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    code: "bastion.host.empty",
                    message: "Bastion host is required.",
                    profileName: profile.name
                ))
            }

            validatePort(profile.bastion.port, code: "bastion.port", label: "Bastion port", profile: profile.name, warnPrivileged: false, issues: &issues)

            if let identityFile = profile.bastion.identityFile, !identityFile.isEmpty {
                let identityURL = PathExpander.expand(identityFile)
                if !FileManager.default.fileExists(atPath: identityURL.path) {
                    issues.append(ValidationIssue(
                        severity: .warning,
                        code: "identity.missing",
                        message: "Identity file does not exist at \(identityFile).",
                        profileName: profile.name
                    ))
                }
            }

            if profile.forwards.isEmpty {
                issues.append(ValidationIssue(
                    severity: .error,
                    code: "forwards.empty",
                    message: "At least one local forward is required.",
                    profileName: profile.name
                ))
            }

            var forwardNames: [String: Int] = [:]
            var localInProfile: [ForwardEndpoint: Int] = [:]
            for forward in profile.forwards {
                forwardNames[forward.name, default: 0] += 1
                localInProfile[normalized(endpoint: forward.local), default: 0] += 1
                validatePort(forward.local.port, code: "forward.local.port", label: "Local port", profile: profile.name, warnPrivileged: true, issues: &issues)
                validatePort(forward.remote.port, code: "forward.remote.port", label: "Remote port", profile: profile.name, warnPrivileged: false, issues: &issues)

                if forward.local.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(ValidationIssue(
                        severity: .error,
                        code: "forward.local.host.empty",
                        message: "Local host is required for forward '\(forward.name)'.",
                        profileName: profile.name
                    ))
                }
                if forward.remote.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    issues.append(ValidationIssue(
                        severity: .error,
                        code: "forward.remote.host.empty",
                        message: "Remote host is required for forward '\(forward.name)'.",
                        profileName: profile.name
                    ))
                }

                if profile.enabled {
                    localPorts[normalized(endpoint: forward.local), default: []].append(profile.name)
                }
            }

            for (name, count) in forwardNames where count > 1 {
                issues.append(ValidationIssue(
                    severity: .warning,
                    code: "forward.name.duplicate",
                    message: "Forward name '\(name)' appears \(count) times in the profile.",
                    profileName: profile.name
                ))
            }

            for (endpoint, count) in localInProfile where count > 1 {
                issues.append(ValidationIssue(
                    severity: .error,
                    code: "forward.local.duplicate",
                    message: "Local endpoint \(endpoint.host):\(endpoint.port) is duplicated inside the profile.",
                    profileName: profile.name
                ))
            }
        }

        for (name, count) in profileNames where count > 1 {
            issues.append(ValidationIssue(
                severity: .error,
                code: "profile.name.duplicate",
                message: "Profile name '\(name)' appears \(count) times."
            ))
        }

        for (endpoint, profiles) in localPorts where Set(profiles).count > 1 {
            issues.append(ValidationIssue(
                severity: .error,
                code: "forward.local.conflict",
                message: "Enabled profiles share local endpoint \(endpoint.host):\(endpoint.port): \(profiles.joined(separator: ", "))."
            ))
        }

        if checkLivePorts {
            var checked: Set<ForwardEndpoint> = []
            for profile in config.profiles where profile.enabled {
                for forward in profile.forwards {
                    let endpoint = normalized(endpoint: forward.local)
                    guard !checked.contains(endpoint), isValidPort(endpoint.port) else {
                        continue
                    }
                    checked.insert(endpoint)
                    if !PortProbe.canBind(host: endpoint.host, port: endpoint.port) {
                        issues.append(ValidationIssue(
                            severity: .error,
                            code: "forward.local.inUse",
                            message: "Local endpoint \(endpoint.host):\(endpoint.port) is already in use.",
                            profileName: profile.name
                        ))
                    }
                }
            }
        }

        return issues.sorted { lhs, rhs in
            if lhs.severity == rhs.severity {
                return lhs.code < rhs.code
            }
            return lhs.severity > rhs.severity
        }
    }

    private static func validatePort(
        _ port: Int,
        code: String,
        label: String,
        profile: String,
        warnPrivileged: Bool,
        issues: inout [ValidationIssue]
    ) {
        guard isValidPort(port) else {
            issues.append(ValidationIssue(
                severity: .error,
                code: code,
                message: "\(label) must be between 1 and 65535, got \(port).",
                profileName: profile
            ))
            return
        }

        if warnPrivileged && port < 1024 {
            issues.append(ValidationIssue(
                severity: .warning,
                code: "\(code).privileged",
                message: "\(label) \(port) may require elevated privileges.",
                profileName: profile
            ))
        }
    }

    private static func isValidPort(_ port: Int) -> Bool {
        (1...65535).contains(port)
    }

    private static func normalized(endpoint: ForwardEndpoint) -> ForwardEndpoint {
        let host: String
        switch endpoint.host {
        case "localhost":
            host = "127.0.0.1"
        default:
            host = endpoint.host
        }
        return ForwardEndpoint(host: host, port: endpoint.port)
    }
}

public enum PortProbe {
    public static func canBind(host: String, port: Int) -> Bool {
        guard (1...65535).contains(port) else {
            return false
        }

        let normalizedHost = host == "localhost" ? "127.0.0.1" : host
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            return false
        }
        defer { close(fd) }

        var value: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian

        if normalizedHost == "0.0.0.0" || normalizedHost == "*" {
            address.sin_addr = in_addr(s_addr: INADDR_ANY)
        } else {
            guard inet_pton(AF_INET, normalizedHost, &address.sin_addr) == 1 else {
                return true
            }
        }

        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}
