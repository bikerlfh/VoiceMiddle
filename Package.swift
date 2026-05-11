// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceMiddle",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "VMCore", targets: ["VMCore"]),
        .library(name: "VMAudio", targets: ["VMAudio"]),
        .library(name: "VMScribe", targets: ["VMScribe"]),
        .library(name: "VMFlash", targets: ["VMFlash"]),
        .library(name: "VMTranslators", targets: ["VMTranslators"]),
        .library(name: "VMPipeline", targets: ["VMPipeline"]),
    ],
    targets: [
        .target(name: "VMCore"),
        .target(name: "VMAudio", dependencies: ["VMCore"]),
        .target(name: "VMScribe", dependencies: ["VMCore"]),
        .target(name: "VMFlash", dependencies: ["VMCore"]),
        .target(name: "VMTranslators", dependencies: ["VMCore"]),
        .target(name: "VMPipeline", dependencies: [
            "VMCore", "VMAudio", "VMScribe", "VMFlash", "VMTranslators",
        ]),
        .testTarget(name: "VMCoreTests", dependencies: ["VMCore"]),
        .testTarget(name: "VMAudioTests", dependencies: ["VMAudio"]),
        .testTarget(name: "VMScribeTests", dependencies: ["VMScribe"]),
        .testTarget(name: "VMFlashTests", dependencies: ["VMFlash"]),
        .testTarget(name: "VMTranslatorsTests", dependencies: ["VMTranslators"]),
        .testTarget(name: "VMPipelineTests", dependencies: ["VMPipeline"]),
    ]
)
