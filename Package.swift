// swift-tools-version: 5.4
import PackageDescription

let package = Package(
    name: "MacBastion",
    products: [
        .library(name: "MacBastionCore", targets: ["MacBastionCore"]),
        .executable(name: "mbastion", targets: ["mbastion"]),
        .executable(name: "MacBastionMenu", targets: ["MacBastionMenu"])
    ],
    dependencies: [],
    targets: [
        .target(name: "MacBastionCore"),
        .executableTarget(
            name: "mbastion",
            dependencies: ["MacBastionCore"]
        ),
        .executableTarget(
            name: "MacBastionMenu",
            dependencies: ["MacBastionCore"]
        ),
        .testTarget(
            name: "MacBastionCoreTests",
            dependencies: ["MacBastionCore"]
        )
    ]
)
