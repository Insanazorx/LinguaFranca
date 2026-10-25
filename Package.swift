// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LinguaFranca",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LinguaFrancaCore", targets: ["LinguaFrancaCore"]),
        .library(name: "LinguaFrancaInference", targets: ["LinguaFrancaInference"]),
        .executable(name: "model-smoke", targets: ["ModelSmoke"]),
        .executable(name: "replacement-smoke", targets: ["ReplacementSmoke"]),
        .executable(name: "speech-smoke", targets: ["SpeechSmoke"])
    ],
    dependencies: [
        .package(path: "Vendor/GRDB.swift")
    ],
    targets: [
        .target(name: "LinguaFrancaCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")], path: "Core"),
        .binaryTarget(name: "llama", path: "Vendor/llama.xcframework"),
        .binaryTarget(name: "SpeechMac", path: "Vendor/Speech/Sherpa-macos.xcframework"),
        .binaryTarget(name: "SpeechIOS", path: "Vendor/Speech/Sherpa-ios.xcframework"),
        .binaryTarget(name: "OnnxMac", path: "Vendor/Speech/Onnx-macos.xcframework"),
        .binaryTarget(name: "OnnxIOS", path: "Vendor/Speech/Onnx-ios.xcframework"),
        .target(name: "LinguaFrancaInference", dependencies: ["LinguaFrancaCore", "llama",
            .target(name:"SpeechMac",condition:.when(platforms:[.macOS])), .target(name:"SpeechIOS",condition:.when(platforms:[.iOS])),
            .target(name:"OnnxMac",condition:.when(platforms:[.macOS])), .target(name:"OnnxIOS",condition:.when(platforms:[.iOS]))], path: "Inference",
                linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate"), .linkedFramework("Metal"), .linkedFramework("Foundation"), .linkedFramework("CoreML")]),
        .executableTarget(name: "ModelSmoke", dependencies: ["LinguaFrancaInference", "LinguaFrancaCore"], path: "Tools/ModelSmoke"),
        .executableTarget(name: "ReplacementSmoke", dependencies: ["LinguaFrancaCore"], path: "Tools/ReplacementSmoke"),
        .executableTarget(name: "SpeechSmoke", dependencies: ["LinguaFrancaInference", "LinguaFrancaCore"], path: "Tools/SpeechSmoke"),
        .testTarget(name: "LinguaFrancaCoreTests", dependencies: ["LinguaFrancaCore", .product(name: "GRDB", package: "GRDB.swift")], path: "Tests/CoreTests"),
        .testTarget(name: "LinguaFrancaInferenceTests", dependencies: ["LinguaFrancaCore", "LinguaFrancaInference"], path: "Tests/InferenceTests")
    ],
    swiftLanguageModes: [.v6]
)
