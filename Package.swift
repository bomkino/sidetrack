// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Sidetrack",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Sidetrack", targets: ["Sidetrack"]),
        .executable(name: "SidetrackChecks", targets: ["SidetrackChecks"])
    ],
    targets: [
        .target(name: "SidetrackCore", exclude: ["Icon\r"]),
        .executableTarget(name: "Sidetrack", dependencies: ["SidetrackCore"], exclude: ["Icon\r"]),
        .executableTarget(
            name: "SidetrackChecks",
            dependencies: ["SidetrackCore"],
            path: "Tests/SidetrackCoreTests",
            exclude: ["Icon\r"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
