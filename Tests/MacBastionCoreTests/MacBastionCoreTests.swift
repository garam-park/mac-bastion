import XCTest
@testable import MacBastionCore

final class MacBastionCoreTests: XCTestCase {
    func testParsesConfig() throws {
        let yaml = ConfigStore().sampleConfigYAML
        let value = try YAMLParser().parse(yaml)
        let config = try ConfigCodec.decode(value)

        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "dev-db")
        XCTAssertEqual(config.profiles[0].forwards[0].local.port, 15432)
    }

    func testValidationCatchesDuplicateLocalPorts() {
        let profileA = BastionProfile(
            name: "a",
            bastion: BastionHost(host: "bastion.example.com"),
            forwards: [LocalForward(name: "db", local: ForwardEndpoint(host: "localhost", port: 15432), remote: ForwardEndpoint(host: "db-a", port: 5432))]
        )
        let profileB = BastionProfile(
            name: "b",
            bastion: BastionHost(host: "bastion.example.com"),
            forwards: [LocalForward(name: "db", local: ForwardEndpoint(host: "127.0.0.1", port: 15432), remote: ForwardEndpoint(host: "db-b", port: 5432))]
        )

        let issues = ConfigValidator.validate(BastionConfig(profiles: [profileA, profileB]))
        XCTAssertTrue(issues.contains { $0.code == "forward.local.conflict" && $0.severity == .error })
    }

    func testSSHCommandUsesArgumentArrayShape() {
        let profile = BastionProfile(
            name: "dev",
            bastion: BastionHost(host: "bastion.example.com", user: "ec2-user", port: 2222, identityFile: "~/.ssh/id_ed25519"),
            forwards: [LocalForward(name: "api", local: ForwardEndpoint(host: "127.0.0.1", port: 18080), remote: ForwardEndpoint(host: "api.internal", port: 80))]
        )

        let command = SSHCommandBuilder.command(for: profile)
        XCTAssertEqual(command.executable, "/usr/bin/ssh")
        XCTAssertTrue(command.arguments.contains("-L"))
        XCTAssertTrue(command.arguments.contains("127.0.0.1:18080:api.internal:80"))
        XCTAssertTrue(command.arguments.contains("ec2-user@bastion.example.com"))
        XCTAssertTrue(command.rendered.contains("ExitOnForwardFailure=yes"))
    }

    func testExportRoundTrip() throws {
        let profile = BastionProfile(
            name: "prod-api",
            description: "API tunnel",
            tags: ["prod", "api"],
            bastion: BastionHost(host: "bastion.example.com", user: "deploy", sshOptions: ["StrictHostKeyChecking": "accept-new"]),
            forwards: [LocalForward(name: "http", local: ForwardEndpoint(host: "127.0.0.1", port: 18080), remote: ForwardEndpoint(host: "api.internal", port: 80))]
        )
        let original = BastionConfig(currentProfile: "prod-api", profiles: [profile])
        let yaml = ConfigCodec.encode(original)
        let decoded = try ConfigCodec.decode(YAMLParser().parse(yaml))

        XCTAssertEqual(decoded, original)
    }
}
