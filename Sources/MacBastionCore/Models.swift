import Foundation

public struct BastionConfig: Equatable {
    public var apiVersion: String
    public var kind: String
    public var currentProfile: String?
    public var includes: [String]
    public var profiles: [BastionProfile]

    public init(
        apiVersion: String = "mac-bastion/v1",
        kind: String = "BastionConfig",
        currentProfile: String? = nil,
        includes: [String] = [],
        profiles: [BastionProfile] = []
    ) {
        self.apiVersion = apiVersion
        self.kind = kind
        self.currentProfile = currentProfile
        self.includes = includes
        self.profiles = profiles
    }
}

public struct BastionProfile: Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var description: String?
    public var enabled: Bool
    public var tags: [String]
    public var bastion: BastionHost
    public var forwards: [LocalForward]

    public init(
        name: String,
        description: String? = nil,
        enabled: Bool = true,
        tags: [String] = [],
        bastion: BastionHost,
        forwards: [LocalForward]
    ) {
        self.name = name
        self.description = description
        self.enabled = enabled
        self.tags = tags
        self.bastion = bastion
        self.forwards = forwards
    }
}

public struct BastionHost: Equatable {
    public var host: String
    public var user: String?
    public var port: Int
    public var identityFile: String?
    public var sshOptions: [String: String]

    public init(
        host: String,
        user: String? = nil,
        port: Int = 22,
        identityFile: String? = nil,
        sshOptions: [String: String] = [:]
    ) {
        self.host = host
        self.user = user
        self.port = port
        self.identityFile = identityFile
        self.sshOptions = sshOptions
    }
}

public struct LocalForward: Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var local: ForwardEndpoint
    public var remote: ForwardEndpoint

    public init(name: String, local: ForwardEndpoint, remote: ForwardEndpoint) {
        self.name = name
        self.local = local
        self.remote = remote
    }
}

public struct ForwardEndpoint: Equatable, Hashable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}
