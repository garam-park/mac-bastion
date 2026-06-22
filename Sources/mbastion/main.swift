import Foundation
import MacBastionCore

@main
struct MBastionCLI {
    static func main() {
        do {
            try run(Array(CommandLine.arguments.dropFirst()))
        } catch let error as MacBastionError {
            printError(error.description)
            if case let .validationFailed(issues) = error {
                printIssues(issues)
            }
            Foundation.exit(1)
        } catch {
            printError(String(describing: error))
            Foundation.exit(1)
        }
    }

    private static func run(_ arguments: [String]) throws {
        var options = CLIOptions(arguments: arguments)
        guard let command = options.popCommand() else {
            printHelp()
            return
        }

        let store = ConfigStore()
        let runtime = TunnelRuntime()

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "init":
            let url = try store.ensureSampleConfig(path: options.value(for: "--config"), force: options.contains("--force"))
            print("Created config at \(url.path)")
        case "list":
            let loaded = try store.load(path: options.value(for: "--config"))
            printProfileList(loaded.config, runtime: runtime)
        case "validate":
            let loaded = try store.load(path: options.value(for: "--config"))
            let issues = ConfigValidator.validate(loaded.config, checkLivePorts: options.contains("--live"))
            printIssues(issues)
            if issues.contains(where: { $0.severity == .error }) {
                Foundation.exit(1)
            }
        case "render-ssh":
            let loaded = try store.load(path: options.value(for: "--config"))
            let profile = try requiredProfile(from: loaded.config, name: options.popValue("profile"))
            print(SSHCommandBuilder.command(for: profile).rendered)
        case "start":
            let loaded = try store.load(path: options.value(for: "--config"))
            let profile = try requiredProfile(from: loaded.config, name: options.popValue("profile"))
            let status = try runtime.start(profile)
            printStatus(status)
        case "start-all":
            let loaded = try store.load(path: options.value(for: "--config"))
            let issues = ConfigValidator.validate(loaded.config, checkLivePorts: false)
            let errors = issues.filter { $0.severity == .error }
            guard errors.isEmpty else {
                throw MacBastionError.validationFailed(issues)
            }
            for profile in loaded.config.profiles where profile.enabled {
                printStatus(try runtime.start(profile))
            }
        case "stop":
            let name = try options.popRequiredValue("profile")
            let status = try runtime.stop(profileName: name)
            printStatus(status)
        case "stop-all":
            let loaded = try store.load(path: options.value(for: "--config"))
            let configNames = Set(loaded.config.profiles.map { $0.name })
            for profile in loaded.config.profiles {
                printStatus(try runtime.stop(profileName: profile.name))
            }
            for record in runtime.allRuntimeRecords() where !configNames.contains(record.profileName) {
                printStatus(try runtime.stop(profileName: record.profileName))
            }
        case "restart":
            let loaded = try store.load(path: options.value(for: "--config"))
            let profile = try requiredProfile(from: loaded.config, name: options.popValue("profile"))
            let status = try runtime.restart(profile)
            printStatus(status)
        case "status":
            let loaded = try store.load(path: options.value(for: "--config"))
            if let name = options.popValue("profile") {
                let profile = try requiredProfile(from: loaded.config, name: name)
                printStatus(runtime.status(for: profile))
            } else {
                for status in runtime.statuses(for: loaded.config.profiles) {
                    printStatus(status)
                }
            }
        case "logs":
            let name = try options.popRequiredValue("profile")
            print(runtime.tailLog(for: name), terminator: "")
        case "import":
            let source = PathExpander.expand(try options.popRequiredValue("file"))
            let destination = store.configURL(path: options.value(for: "--config"))
            let mode = ImportMode(rawValue: options.value(for: "--mode") ?? "merge") ?? .merge
            try store.importConfig(from: source, into: destination, mode: mode)
            print("Imported \(source.path) into \(destination.path) using \(mode.rawValue) mode")
        case "export":
            let loaded = try store.load(path: options.value(for: "--config"))
            let yaml = try store.exportYAML(config: loaded.config, profileName: options.value(for: "--profile"))
            if let output = options.value(for: "--output") {
                let outputURL = PathExpander.expand(output)
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try yaml.write(to: outputURL, atomically: true, encoding: .utf8)
                print("Exported to \(outputURL.path)")
            } else {
                print(yaml, terminator: "")
            }
        case "doctor":
            print("Config: \(store.configURL(path: options.value(for: "--config")).path)")
            print("Runtime: \(runtime.runtimeDirectory.path)")
            print("Logs: \(runtime.logDirectory.path)")
            print("ssh: /usr/bin/ssh")
        default:
            throw MacBastionError.message("Unknown command: \(command)")
        }
    }

    private static func requiredProfile(from config: BastionConfig, name: String?) throws -> BastionProfile {
        let selectedName = name ?? config.currentProfile
        guard let selectedName, !selectedName.isEmpty else {
            throw MacBastionError.message("Profile name is required")
        }
        guard let profile = config.profiles.first(where: { $0.name == selectedName }) else {
            throw MacBastionError.message("Unknown profile: \(selectedName)")
        }
        return profile
    }

    private static func printProfileList(_ config: BastionConfig, runtime: TunnelRuntime) {
        let statuses = Dictionary(uniqueKeysWithValues: runtime.statuses(for: config.profiles).map { ($0.profileName, $0) })
        print("PROFILE\tSTATE\tFORWARDS\tBASTION")
        for profile in config.profiles {
            let state = statuses[profile.name]?.state.rawValue ?? "stopped"
            let forwards = profile.forwards.map { "\($0.local.host):\($0.local.port)->\($0.remote.host):\($0.remote.port)" }.joined(separator: ",")
            let user = profile.bastion.user.map { "\($0)@" } ?? ""
            print("\(profile.name)\t\(state)\t\(forwards)\t\(user)\(profile.bastion.host)")
        }
    }

    private static func printIssues(_ issues: [ValidationIssue]) {
        if issues.isEmpty {
            print("OK: no validation issues")
            return
        }
        for issue in issues {
            print(issue.description)
        }
    }

    private static func printStatus(_ status: TunnelStatus) {
        var parts = ["\(status.profileName): \(status.state.rawValue)"]
        if let pid = status.pid {
            parts.append("pid=\(pid)")
        }
        if let message = status.message {
            parts.append(message)
        }
        if let logPath = status.logPath {
            parts.append("log=\(logPath)")
        }
        print(parts.joined(separator: " "))
    }

    private static func printError(_ message: String) {
        FileHandle.standardError.write(Data("ERROR: \(message)\n".utf8))
    }

    private static func printHelp() {
        print(
            """
            mbastion - macOS bastion tunnel manager

            Usage:
              mbastion init [--config PATH] [--force]
              mbastion list [--config PATH]
              mbastion validate [--config PATH] [--live]
              mbastion render-ssh [--config PATH] [PROFILE]
              mbastion start [--config PATH] [PROFILE]
              mbastion start-all [--config PATH]
              mbastion stop PROFILE
              mbastion stop-all [--config PATH]
              mbastion restart [--config PATH] [PROFILE]
              mbastion status [--config PATH] [PROFILE]
              mbastion logs PROFILE
              mbastion import FILE [--config PATH] [--mode merge|replace]
              mbastion export [--config PATH] [--profile PROFILE] [--output PATH]
              mbastion doctor [--config PATH]

            Default config:
              ~/.config/mac-bastion/config.yaml
            """
        )
    }
}

private struct CLIOptions {
    private var positionals: [String] = []
    private var flags: Set<String> = []
    private var values: [String: String] = [:]

    init(arguments: [String]) {
        var index = 0
        let valueFlags: Set<String> = ["--config", "--mode", "--profile", "--output"]
        while index < arguments.count {
            let argument = arguments[index]
            if argument.hasPrefix("--") {
                if valueFlags.contains(argument), index + 1 < arguments.count {
                    values[argument] = arguments[index + 1]
                    index += 2
                } else {
                    flags.insert(argument)
                    index += 1
                }
            } else {
                positionals.append(argument)
                index += 1
            }
        }
    }

    mutating func popCommand() -> String? {
        guard !positionals.isEmpty else {
            return nil
        }
        return positionals.removeFirst()
    }

    func contains(_ flag: String) -> Bool {
        flags.contains(flag) || values[flag] != nil
    }

    func value(for flag: String) -> String? {
        values[flag]
    }

    mutating func popValue(_ label: String) -> String? {
        guard !positionals.isEmpty else {
            return nil
        }
        return positionals.removeFirst()
    }

    mutating func popRequiredValue(_ label: String) throws -> String {
        guard let value = popValue(label) else {
            throw MacBastionError.message("\(label) is required")
        }
        return value
    }
}
