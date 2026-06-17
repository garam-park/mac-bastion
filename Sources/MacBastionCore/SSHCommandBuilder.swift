import Foundation

public struct SSHCommand {
    public var executable: String
    public var arguments: [String]

    public init(executable: String = "/usr/bin/ssh", arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    public var rendered: String {
        ([executable] + arguments).map(Self.shellEscaped).joined(separator: " ")
    }

    private static func shellEscaped(_ value: String) -> String {
        let safeCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-=.,/:@%")
        if value.rangeOfCharacter(from: safeCharacters.inverted) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public enum SSHCommandBuilder {
    public static func command(for profile: BastionProfile) -> SSHCommand {
        var arguments: [String] = [
            "-N",
            "-T",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3"
        ]

        for forward in profile.forwards {
            arguments.append("-L")
            arguments.append("\(forward.local.host):\(forward.local.port):\(forward.remote.host):\(forward.remote.port)")
        }

        if profile.bastion.port != 22 {
            arguments.append(contentsOf: ["-p", String(profile.bastion.port)])
        }

        if let identityFile = profile.bastion.identityFile, !identityFile.isEmpty {
            arguments.append(contentsOf: ["-i", NSString(string: identityFile).expandingTildeInPath])
        }

        for key in profile.bastion.sshOptions.keys.sorted() {
            guard let value = profile.bastion.sshOptions[key], !value.isEmpty else {
                continue
            }
            arguments.append(contentsOf: ["-o", "\(key)=\(value)"])
        }

        let target = [profile.bastion.user, profile.bastion.host]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
        if target.count == 2 {
            arguments.append("\(target[0])@\(target[1])")
        } else {
            arguments.append(profile.bastion.host)
        }

        return SSHCommand(arguments: arguments)
    }
}
