import Foundation

public struct LoadedConfig {
    public var config: BastionConfig
    public var rootURL: URL
    public var sourceURLs: [URL]

    public init(config: BastionConfig, rootURL: URL, sourceURLs: [URL]) {
        self.config = config
        self.rootURL = rootURL
        self.sourceURLs = sourceURLs
    }
}

public enum ImportMode: String {
    case merge
    case replace
}

public final class ConfigStore {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public var defaultConfigURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/mac-bastion/config.yaml")
    }

    public var supportDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacBastion")
    }

    public func configURL(path: String? = nil) -> URL {
        guard let path, !path.isEmpty else {
            return defaultConfigURL
        }
        return PathExpander.expand(path)
    }

    public func load(path: String? = nil) throws -> LoadedConfig {
        let url = configURL(path: path)
        guard fileManager.fileExists(atPath: url.path) else {
            throw MacBastionError.fileNotFound(url.path)
        }

        var visiting: Set<String> = []
        var visited: Set<String> = []
        let loaded = try loadFile(url: url, visiting: &visiting, visited: &visited)
        return LoadedConfig(config: loaded.config, rootURL: url, sourceURLs: loaded.sources)
    }

    public func ensureSampleConfig(path: String? = nil, force: Bool = false) throws -> URL {
        let url = configURL(path: path)
        if fileManager.fileExists(atPath: url.path), !force {
            return url
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try sampleConfigYAML.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func write(_ config: BastionConfig, to url: URL) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try ConfigCodec.encode(config).write(to: url, atomically: true, encoding: .utf8)
    }

    public func importConfig(from sourceURL: URL, into destinationURL: URL, mode: ImportMode) throws {
        let importedText = try String(contentsOf: sourceURL, encoding: .utf8)
        let imported = try ConfigCodec.decode(YAMLParser().parse(importedText), sourceDescription: sourceURL.path)

        let nextConfig: BastionConfig
        if mode == .replace || !fileManager.fileExists(atPath: destinationURL.path) {
            nextConfig = imported
        } else {
            let existingText = try String(contentsOf: destinationURL, encoding: .utf8)
            var existing = try ConfigCodec.decode(YAMLParser().parse(existingText), sourceDescription: destinationURL.path)
            for profile in imported.profiles {
                if let index = existing.profiles.firstIndex(where: { $0.name == profile.name }) {
                    existing.profiles[index] = profile
                } else {
                    existing.profiles.append(profile)
                }
            }
            nextConfig = existing
        }

        let issues = ConfigValidator.validate(nextConfig, checkLivePorts: false)
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw MacBastionError.validationFailed(issues)
        }

        try backupIfExists(destinationURL)
        try write(nextConfig, to: destinationURL)
    }

    public func exportYAML(config: BastionConfig, profileName: String? = nil) throws -> String {
        if let profileName {
            guard let profile = config.profiles.first(where: { $0.name == profileName }) else {
                throw MacBastionError.message("Unknown profile: \(profileName)")
            }
            return ConfigCodec.encode(profile: profile)
        }
        return ConfigCodec.encode(config)
    }

    private func loadFile(url: URL, visiting: inout Set<String>, visited: inout Set<String>) throws -> (config: BastionConfig, sources: [URL]) {
        let path = url.standardizedFileURL.path
        // Already fully loaded via a different include path (diamond) — skip to avoid duplicates.
        if visited.contains(path) {
            return (BastionConfig(), [])
        }
        guard !visiting.contains(path) else {
            throw MacBastionError.parse("Include cycle detected at \(path)")
        }
        visiting.insert(path)
        visited.insert(path)

        let text = try String(contentsOf: url, encoding: .utf8)
        var config = try ConfigCodec.decode(YAMLParser().parse(text), sourceDescription: path)
        var sources = [url]
        let baseURL = url.deletingLastPathComponent()

        for include in config.includes {
            for includeURL in try expandInclude(include, relativeTo: baseURL) {
                guard fileManager.fileExists(atPath: includeURL.path) else {
                    throw MacBastionError.fileNotFound(includeURL.path)
                }
                let loaded = try loadFile(url: includeURL, visiting: &visiting, visited: &visited)
                config.profiles.append(contentsOf: loaded.config.profiles)
                sources.append(contentsOf: loaded.sources)
            }
        }

        visiting.remove(path)
        return (config, sources)
    }

    private func expandInclude(_ pattern: String, relativeTo baseURL: URL) throws -> [URL] {
        let absolutePattern = PathExpander.expand(pattern, relativeTo: baseURL).path
        guard absolutePattern.contains("*") else {
            return [URL(fileURLWithPath: absolutePattern)]
        }

        let wildcardIndex = absolutePattern.firstIndex(of: "*")!
        let prefix = String(absolutePattern[..<wildcardIndex])
        let basePath = prefix.contains("/")
            ? String(prefix[..<(prefix.lastIndex(of: "/") ?? prefix.startIndex)])
            : fileManager.currentDirectoryPath
        let baseURL = URL(fileURLWithPath: basePath.isEmpty ? "/" : basePath)
        let regex = try NSRegularExpression(pattern: globToRegex(absolutePattern))
        let subpaths = (try? fileManager.subpathsOfDirectory(atPath: baseURL.path)) ?? []

        return subpaths
            .map { baseURL.appendingPathComponent($0).standardizedFileURL }
            .filter { url in
                let range = NSRange(location: 0, length: url.path.utf16.count)
                return regex.firstMatch(in: url.path, range: range) != nil
            }
            .sorted { $0.path < $1.path }
    }

    private func globToRegex(_ pattern: String) -> String {
        var regex = "^"
        for character in pattern {
            switch character {
            case "*":
                regex += "[^/]*"
            case ".":
                regex += "\\."
            case "/":
                regex += "/"
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        return regex + "$"
    }

    private func backupIfExists(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backup = url.deletingPathExtension()
            .appendingPathExtension("\(stamp).bak.yaml")
        try? fileManager.removeItem(at: backup)
        try fileManager.copyItem(at: url, to: backup)
    }

    public var sampleConfigYAML: String {
        """
        apiVersion: mac-bastion/v1
        kind: BastionConfig
        currentProfile: dev-db
        includes:
          - profiles/*.yaml
        profiles:
          - name: dev-db
            description: Local Postgres through the development bastion
            enabled: true
            tags: [dev, database]
            bastion:
              host: bastion.example.com
              user: ec2-user
              port: 22
              identityFile: ~/.ssh/id_ed25519
              sshOptions:
                StrictHostKeyChecking: accept-new
            forwards:
              - name: postgres
                local:
                  host: 127.0.0.1
                  port: 15432
                remote:
                  host: postgres.internal
                  port: 5432
        """
    }
}
