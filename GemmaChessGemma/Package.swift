// swift-tools-version: 6.0
import PackageDescription

// Optional Gemma-via-MLX coach backend (U15). Kept as a SEPARATE package so the
// large MLX dependency and the multi-GB model never burden the FM-first device
// build. Apps that must support non-Apple-Intelligence devices (iOS 18–25 or
// older hardware) link this and append `MLXGemmaCoach` to the orchestrator's
// backend list; Apple-Intelligence devices never need it.
let package = Package(
    name: "GemmaChessGemma",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "GemmaChessGemma", targets: ["GemmaChessGemma"]),
    ],
    dependencies: [
        .package(path: ".."),
        .package(url: "https://github.com/ml-explore/mlx-swift-examples.git", exact: "2.25.9"),
    ],
    targets: [
        .target(
            name: "GemmaChessGemma",
            dependencies: [
                .product(name: "GemmaChessCore", package: "GemmaChess"),
                .product(name: "MLXLLM", package: "mlx-swift-examples"),
                .product(name: "MLXLMCommon", package: "mlx-swift-examples"),
            ],
            path: "Sources/GemmaChessGemma"
        ),
    ]
)
