// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WebcamController",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "UVCCore",
            targets: ["UVCCore"]
        ),
        .executable(
            name: "WebcamControllerApp",
            targets: ["WebcamControllerApp"]
        ),
        .executable(
            name: "webcamctl",
            targets: ["webcamctl"]
        ),
        .executable(
            name: "UVCCoreTests",
            targets: ["UVCCoreTests"]
        )
    ],
    targets: [
        .target(
            name: "CUVCHardware",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation")
            ]
        ),
        .target(
            name: "UVCCore",
            dependencies: ["CUVCHardware"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreAudio")
            ]
        ),
        .executableTarget(
            name: "WebcamControllerApp",
            dependencies: ["UVCCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "webcamctl",
            dependencies: ["UVCCore"],
            linkerSettings: [
                .linkedFramework("Foundation")
            ]
        ),
        .executableTarget(
            name: "UVCCoreTests",
            dependencies: ["UVCCore", "CUVCHardware"],
            path: "Tests/UVCCoreTests"
        )
    ]
)
