import Foundation

public enum ConfigCodec {
    public static func decode(_ value: YAMLValue, sourceDescription: String = "config") throws -> BastionConfig {
        let root = try value.mapValue(path: sourceDescription)

        let apiVersion = root.string("apiVersion") ?? "mac-bastion/v1"
        let kind = root.string("kind") ?? "BastionConfig"
        let currentProfile = root.string("currentProfile") ?? root.string("currentContext")
        let includes = root.stringArray("includes") ?? root.stringArray("include") ?? root.singleStringArray("include")

        var profiles: [BastionProfile] = []
        if let profileValue = root["profile"] {
            profiles.append(try decodeProfile(profileValue, path: "\(sourceDescription).profile"))
        }
        if let profilesValue = root["profiles"] {
            profiles.append(contentsOf: try profilesValue.arrayValue(path: "\(sourceDescription).profiles").enumerated().map { index, value in
                try decodeProfile(value, path: "\(sourceDescription).profiles[\(index)]")
            })
        }

        return BastionConfig(
            apiVersion: apiVersion,
            kind: kind,
            currentProfile: currentProfile,
            includes: includes,
            profiles: profiles
        )
    }

    public static func encode(_ config: BastionConfig, includeHeaders: Bool = true) -> String {
        var lines: [String] = []
        if includeHeaders {
            lines.append("apiVersion: \(scalar(config.apiVersion))")
            lines.append("kind: \(scalar(config.kind))")
        }
        if let currentProfile = config.currentProfile, !currentProfile.isEmpty {
            lines.append("currentProfile: \(scalar(currentProfile))")
        }
        if !config.includes.isEmpty {
            lines.append("includes:")
            for include in config.includes {
                lines.append("  - \(scalar(include))")
            }
        }
        if config.profiles.isEmpty {
            lines.append("profiles: []")
        } else {
            lines.append("profiles:")
            for profile in config.profiles {
                append(profile: profile, to: &lines, indent: 2)
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func encode(profile: BastionProfile) -> String {
        encode(BastionConfig(profiles: [profile]))
    }

    private static func decodeProfile(_ value: YAMLValue, path: String) throws -> BastionProfile {
        let map = try value.mapValue(path: path)
        let name = try map.requiredString("name", path: path)
        let description = map.string("description")
        let enabled = map.bool("enabled") ?? true
        let tags = map.stringArray("tags") ?? []

        guard let bastionValue = map["bastion"] else {
            throw MacBastionError.parse("Missing \(path).bastion")
        }
        let bastion = try decodeBastion(bastionValue, path: "\(path).bastion")

        guard let forwardsValue = map["forwards"] ?? map["forward"] else {
            throw MacBastionError.parse("Missing \(path).forwards")
        }

        let forwardValues: [YAMLValue]
        if case .array = forwardsValue {
            forwardValues = try forwardsValue.arrayValue(path: "\(path).forwards")
        } else {
            forwardValues = [forwardsValue]
        }

        let forwards = try forwardValues.enumerated().map { index, value in
            try decodeForward(value, path: "\(path).forwards[\(index)]")
        }

        return BastionProfile(
            name: name,
            description: description,
            enabled: enabled,
            tags: tags,
            bastion: bastion,
            forwards: forwards
        )
    }

    private static func decodeBastion(_ value: YAMLValue, path: String) throws -> BastionHost {
        let map = try value.mapValue(path: path)
        let host = try map.requiredString("host", path: path)
        let user = map.string("user")
        let port = map.int("port") ?? 22
        let identityFile = map.string("identityFile")
        let sshOptions = try map["sshOptions"].map { try decodeStringMap($0, path: "\(path).sshOptions") } ?? [:]

        return BastionHost(
            host: host,
            user: user,
            port: port,
            identityFile: identityFile,
            sshOptions: sshOptions
        )
    }

    private static func decodeForward(_ value: YAMLValue, path: String) throws -> LocalForward {
        let map = try value.mapValue(path: path)

        let local: ForwardEndpoint
        if let localValue = map["local"] {
            local = try decodeEndpoint(localValue, path: "\(path).local")
        } else {
            local = ForwardEndpoint(
                host: map.string("localHost") ?? "127.0.0.1",
                port: try map.requiredInt("localPort", path: path)
            )
        }

        let remote: ForwardEndpoint
        if let remoteValue = map["remote"] {
            remote = try decodeEndpoint(remoteValue, path: "\(path).remote")
        } else {
            remote = ForwardEndpoint(
                host: try map.requiredString("remoteHost", path: path),
                port: try map.requiredInt("remotePort", path: path)
            )
        }

        let name = map.string("name") ?? "\(remote.host)-\(remote.port)"
        return LocalForward(name: name, local: local, remote: remote)
    }

    private static func decodeEndpoint(_ value: YAMLValue, path: String) throws -> ForwardEndpoint {
        let map = try value.mapValue(path: path)
        return ForwardEndpoint(
            host: map.string("host") ?? "127.0.0.1",
            port: try map.requiredInt("port", path: path)
        )
    }

    private static func decodeStringMap(_ value: YAMLValue, path: String) throws -> [String: String] {
        let map = try value.mapValue(path: path)
        var result: [String: String] = [:]
        for (key, value) in map {
            result[key] = value.stringRepresentation
        }
        return result
    }

    private static func append(profile: BastionProfile, to lines: inout [String], indent: Int) {
        let pad = String(repeating: " ", count: indent)
        lines.append("\(pad)- name: \(scalar(profile.name))")
        if let description = profile.description, !description.isEmpty {
            lines.append("\(pad)  description: \(scalar(description))")
        }
        lines.append("\(pad)  enabled: \(profile.enabled ? "true" : "false")")
        if !profile.tags.isEmpty {
            lines.append("\(pad)  tags: [\(profile.tags.map(scalar).joined(separator: ", "))]")
        }
        lines.append("\(pad)  bastion:")
        lines.append("\(pad)    host: \(scalar(profile.bastion.host))")
        if let user = profile.bastion.user, !user.isEmpty {
            lines.append("\(pad)    user: \(scalar(user))")
        }
        lines.append("\(pad)    port: \(profile.bastion.port)")
        if let identityFile = profile.bastion.identityFile, !identityFile.isEmpty {
            lines.append("\(pad)    identityFile: \(scalar(identityFile))")
        }
        if !profile.bastion.sshOptions.isEmpty {
            lines.append("\(pad)    sshOptions:")
            for key in profile.bastion.sshOptions.keys.sorted() {
                lines.append("\(pad)      \(key): \(scalar(profile.bastion.sshOptions[key] ?? ""))")
            }
        }
        lines.append("\(pad)  forwards:")
        for forward in profile.forwards {
            lines.append("\(pad)    - name: \(scalar(forward.name))")
            lines.append("\(pad)      local:")
            lines.append("\(pad)        host: \(scalar(forward.local.host))")
            lines.append("\(pad)        port: \(forward.local.port)")
            lines.append("\(pad)      remote:")
            lines.append("\(pad)        host: \(scalar(forward.remote.host))")
            lines.append("\(pad)        port: \(forward.remote.port)")
        }
    }

    private static func scalar(_ value: String) -> String {
        guard !value.isEmpty else {
            return "''"
        }
        let plainCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._/@+-")
        if value.rangeOfCharacter(from: plainCharacters.inverted) == nil,
           value != "true",
           value != "false",
           Int(value) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "''") + "'"
    }
}

private extension YAMLValue {
    func mapValue(path: String) throws -> [String: YAMLValue] {
        guard case let .map(map) = self else {
            throw MacBastionError.parse("Expected map at \(path)")
        }
        return map
    }

    func arrayValue(path: String) throws -> [YAMLValue] {
        guard case let .array(array) = self else {
            throw MacBastionError.parse("Expected array at \(path)")
        }
        return array
    }

    var stringRepresentation: String {
        switch self {
        case let .string(value):
            return value
        case let .int(value):
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case .null:
            return ""
        case .array, .map:
            return ""
        }
    }
}

private extension Dictionary where Key == String, Value == YAMLValue {
    func string(_ key: String) -> String? {
        guard let value = self[key] else {
            return nil
        }
        if case let .string(string) = value {
            return string
        }
        if case let .int(int) = value {
            return String(int)
        }
        return nil
    }

    func requiredString(_ key: String, path: String) throws -> String {
        guard let value = string(key), !value.isEmpty else {
            throw MacBastionError.parse("Missing \(path).\(key)")
        }
        return value
    }

    func int(_ key: String) -> Int? {
        guard let value = self[key] else {
            return nil
        }
        if case let .int(int) = value {
            return int
        }
        if case let .string(string) = value {
            return Int(string)
        }
        return nil
    }

    func requiredInt(_ key: String, path: String) throws -> Int {
        guard let value = int(key) else {
            throw MacBastionError.parse("Missing or invalid \(path).\(key)")
        }
        return value
    }

    func bool(_ key: String) -> Bool? {
        guard let value = self[key] else {
            return nil
        }
        if case let .bool(bool) = value {
            return bool
        }
        if case let .string(string) = value {
            return Bool(string)
        }
        return nil
    }

    func stringArray(_ key: String) -> [String]? {
        guard let value = self[key], case let .array(array) = value else {
            return nil
        }
        return array.compactMap { item in
            if case let .string(string) = item {
                return string
            }
            if case let .int(int) = item {
                return String(int)
            }
            return nil
        }
    }

    func singleStringArray(_ key: String) -> [String] {
        guard let string = string(key) else {
            return []
        }
        return [string]
    }
}
