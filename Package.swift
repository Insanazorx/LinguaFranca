// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "LinguaFranca",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LinguaFrancaCore", targets: ["LinguaFrancaCore"]),
        .library(name: "LinguaFrancaInference", targets: ["LinguaFrancaInference"]),
        .executable(name: "model-smoke", targets: ["ModelSmoke"]),
        .executable(name: "replacement-smoke", targets: ["ReplacementSmoke"])
    ],
    dependencies: [
        .package(path: "Vendor/GRDB.swift")
    ],
    targets: [
        .target(name: "LinguaFrancaCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")], path: "Core"),
        .binaryTarget(name: "llama", path: "Vendor/llama.xcframework"),
        .target(name: "LinguaFrancaInference", dependencies: ["LinguaFrancaCore", "llama"], path: "Inference",
                linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate"), .linkedFramework("Metal"), .linkedFramework("Foundation")]),
        .executableTarget(name: "ModelSmoke", dependencies: ["LinguaFrancaInference", "LinguaFrancaCore"], path: "Tools/ModelSmoke"),
        .executableTarget(name: "ReplacementSmoke", dependencies: ["LinguaFrancaCore"], path: "Tools/ReplacementSmoke"),
        .testTarget(name: "LinguaFrancaCoreTests", dependencies: ["LinguaFrancaCore", .product(name: "GRDB", package: "GRDB.swift")], path: "Tests/CoreTests"),
        .testTarget(name: "LinguaFrancaInferenceTests", dependencies: ["LinguaFrancaCore", "LinguaFrancaInference"], path: "Tests/InferenceTests")
    ],
    swiftLanguageModes: [.v6]
)
