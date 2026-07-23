// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Nudge",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Nudge", targets: ["Nudge"])
    ],
    targets: [
        .executableTarget(
            name: "Nudge",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .testTarget(
            name: "NudgeTests",
            dependencies: ["Nudge"]
        )
    ]
)
