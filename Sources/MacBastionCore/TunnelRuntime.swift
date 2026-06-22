import Darwin
import Foundation

public enum TunnelState: String, Codable {
    case stopped
    case running
    case stale
    case failed
}

public struct TunnelStatus: Codable, Equatable {
    public var profileName: String
    public var state: TunnelState
    public var pid: Int32?
    public var startedAt: Date?
    public var logPath: String?
    public var message: String?

    public init(
        profileName: String,
        state: TunnelState,
        pid: Int32? = nil,
        startedAt: Date? = nil,
        logPath: String? = nil,
        message: String? = nil
    ) {
        self.profileName = profileName
        self.state = state
        self.pid = pid
        self.startedAt = startedAt
        self.logPath = logPath
        self.message = message
    }
}

public struct RuntimeRecord: Codable, Equatable {
    public var profileName: String
    public var pid: Int32
    public var startedAt: Date
    public var command: String
    public var logPath: String
    /// Absolute path of the executable we launched. Optional so records written
    /// by older versions (without this field) still decode; nil falls back to ssh.
    public var executable: String?

    public init(
        profileName: String,
        pid: Int32,
        startedAt: Date,
        command: String,
        logPath: String,
        executable: String? = nil
    ) {
        self.profileName = profileName
        self.pid = pid
        self.startedAt = startedAt
        self.command = command
        self.logPath = logPath
        self.executable = executable
    }
}

public final class TunnelRuntime {
    private let fileManager: FileManager
    public let runtimeDirectory: URL
    public let logDirectory: URL

    public init(
        supportDirectory: URL = ConfigStore().supportDirectoryURL,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        runtimeDirectory = supportDirectory.appendingPathComponent("runtime")
        logDirectory = supportDirectory.appendingPathComponent("logs")
    }

    public func start(_ profile: BastionProfile) throws -> TunnelStatus {
        if let existing = try? record(for: profile.name), Self.isProcessAlive(pid: existing.pid) {
            return TunnelStatus(
                profileName: profile.name,
                state: .running,
                pid: existing.pid,
                startedAt: existing.startedAt,
                logPath: existing.logPath,
                message: "Already running"
            )
        }

        let singleConfig = BastionConfig(profiles: [profile])
        let issues = ConfigValidator.validate(singleConfig, checkLivePorts: true)
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            throw MacBastionError.validationFailed(issues)
        }

        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)

        let command = SSHCommandBuilder.command(for: profile)
        let logURL = logDirectory.appendingPathComponent("\(safeName(profile.name)).log")
        if !fileManager.fileExists(atPath: logURL.path) {
            fileManager.createFile(atPath: logURL.path, contents: nil)
        }

        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()
        let header = "\n[\(Self.dateFormatter.string(from: Date()))] starting \(command.rendered)\n"
        if let data = header.data(using: .utf8) {
            try logHandle.write(contentsOf: data)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardInput = FileHandle(forReadingAtPath: "/dev/null")
        process.standardOutput = logHandle
        process.standardError = logHandle

        try process.run()
        let pid = process.processIdentifier
        Thread.sleep(forTimeInterval: 0.7)

        if !Self.isProcessAlive(pid: pid) {
            let tail = tailLog(at: logURL, maxBytes: 3_000)
            try? logHandle.close()
            throw MacBastionError.message("ssh exited before the tunnel became ready.\n\(tail)")
        }

        let record = RuntimeRecord(
            profileName: profile.name,
            pid: pid,
            startedAt: Date(),
            command: command.rendered,
            logPath: logURL.path,
            executable: command.executable
        )
        try write(record)
        try? logHandle.close()

        return TunnelStatus(
            profileName: profile.name,
            state: .running,
            pid: pid,
            startedAt: record.startedAt,
            logPath: logURL.path,
            message: "Started"
        )
    }

    public func stop(profileName: String) throws -> TunnelStatus {
        guard let record = try? record(for: profileName) else {
            return TunnelStatus(profileName: profileName, state: .stopped, message: "Not running")
        }

        // A stale record's PID may have been recycled by the OS for an unrelated
        // process, so verify the live process before signalling it.
        if Self.isProcessAlive(pid: record.pid) {
            guard let actualPath = Self.processExecutablePath(pid: record.pid) else {
                // Process is alive but we cannot confirm what it is. Leave it and
                // keep the record, rather than abandon a possibly-live tunnel.
                return TunnelStatus(
                    profileName: profileName,
                    state: .running,
                    pid: record.pid,
                    startedAt: record.startedAt,
                    logPath: record.logPath,
                    message: "Could not verify the process; left running. Stop it manually if needed."
                )
            }
            // Only signal when the executable matches what we launched; otherwise
            // the PID was recycled for an unrelated process (shell, editor, ...).
            if actualPath == record.executable ?? SSHCommand.defaultExecutable {
                Darwin.kill(record.pid, SIGTERM)
                for _ in 0..<20 {
                    if !Self.isProcessAlive(pid: record.pid) {
                        break
                    }
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if Self.isProcessAlive(pid: record.pid) {
                    Darwin.kill(record.pid, SIGKILL)
                }
            }
        }

        try? fileManager.removeItem(at: recordURL(for: profileName))
        return TunnelStatus(
            profileName: profileName,
            state: .stopped,
            pid: record.pid,
            startedAt: record.startedAt,
            logPath: record.logPath,
            message: "Stopped"
        )
    }

    public func restart(_ profile: BastionProfile) throws -> TunnelStatus {
        _ = try stop(profileName: profile.name)
        return try start(profile)
    }

    public func status(for profile: BastionProfile) -> TunnelStatus {
        guard let record = try? record(for: profile.name) else {
            return TunnelStatus(profileName: profile.name, state: .stopped)
        }
        if Self.isProcessAlive(pid: record.pid) {
            return TunnelStatus(
                profileName: profile.name,
                state: .running,
                pid: record.pid,
                startedAt: record.startedAt,
                logPath: record.logPath
            )
        }
        return TunnelStatus(
            profileName: profile.name,
            state: .stale,
            pid: record.pid,
            startedAt: record.startedAt,
            logPath: record.logPath,
            message: "Process is no longer running"
        )
    }

    public func statuses(for profiles: [BastionProfile]) -> [TunnelStatus] {
        profiles.map(status(for:))
    }

    public func tailLog(for profileName: String, maxBytes: Int = 4_000) -> String {
        guard let record = try? record(for: profileName) else {
            return ""
        }
        return tailLog(at: URL(fileURLWithPath: record.logPath), maxBytes: maxBytes)
    }

    public func allRuntimeRecords() -> [RuntimeRecord] {
        guard let urls = try? fileManager.contentsOfDirectory(at: runtimeDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        let decoder = Self.makeDecoder()
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> RuntimeRecord? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(RuntimeRecord.self, from: data)
            }
    }

    /// Stops every running tunnel: the named profiles plus any orphaned runtime
    /// records whose profiles were removed from config. Each tunnel is stopped once.
    @discardableResult
    public func stopAll(knownProfileNames: [String]) -> [TunnelStatus] {
        var results: [TunnelStatus] = []
        var stopped: Set<String> = []
        for name in knownProfileNames where !stopped.contains(name) {
            if let status = try? stop(profileName: name) {
                results.append(status)
                stopped.insert(name)
            }
        }
        for record in allRuntimeRecords() where !stopped.contains(record.profileName) {
            if let status = try? stop(profileName: record.profileName) {
                results.append(status)
                stopped.insert(record.profileName)
            }
        }
        return results
    }

    public func record(for profileName: String) throws -> RuntimeRecord {
        let data = try Data(contentsOf: recordURL(for: profileName))
        return try Self.makeDecoder().decode(RuntimeRecord.self, from: data)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func write(_ record: RuntimeRecord) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        try data.write(to: recordURL(for: record.profileName), options: .atomic)
    }

    private func recordURL(for profileName: String) -> URL {
        runtimeDirectory.appendingPathComponent("\(safeName(profileName)).json")
    }

    private func safeName(_ value: String) -> String {
        value.map { character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return String(character)
            }
            return "_"
        }.joined()
    }

    private func tailLog(at url: URL, maxBytes: Int) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return ""
        }
        let suffix = data.suffix(maxBytes)
        return String(data: suffix, encoding: .utf8) ?? ""
    }

    private static func isProcessAlive(pid: Int32) -> Bool {
        if Darwin.kill(pid, 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func processExecutablePath(pid: Int32) -> String? {
        // PROC_PIDPATHINFO_MAXSIZE (4 * MAXPATHLEN); the macro is not exposed to Swift.
        let maxPathSize = 4 * 1024
        var buffer = [CChar](repeating: 0, count: maxPathSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
