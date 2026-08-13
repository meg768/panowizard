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
        .target(
            name: "OpenCVBridge",
            path: "Sources/OpenCVBridge",
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags([
                    "-std=c++17",
                    "-IVendor/OpenCV/include/opencv5"
                ])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-LVendor/OpenCV/lib",
                    "-lopencv_features",
                    "-lopencv_calib",
                    "-lopencv_imgcodecs",
                    "-lopencv_imgproc",
                    "-lopencv_geometry",
                    "-lopencv_flann",
                    "-lopencv_core",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@loader_path/../Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "Vendor/OpenCV/lib"
                ])
            ]
        ),
        .executableTarget(
            name: "PanoWizard",
            dependencies: ["OpenCVBridge"],
            path: "Sources/PanoWizard",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PanoWizardTests",
            dependencies: ["PanoWizard"],
            path: "Tests/PanoWizardTests"
        )
    ],
    cxxLanguageStandard: .cxx17
)
