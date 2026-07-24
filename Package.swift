// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PanoWizard",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "PanoWizard", targets: ["PanoWizard"])
    ],
    targets: [
        .executableTarget(
            name: "PanoWizard",
            path: "Sources/PanoWizard"
        ),
        .testTarget(
            name: "PanoWizardTests",
            dependencies: ["PanoWizard"],
            path: "Tests/PanoWizardTests"
        )
    ]
)
