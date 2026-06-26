// swift-tools-version: 6.0
import PackageDescription

// GemmaChessCore — the cross-platform core shared by the iOS and macOS apps.
// Holds chess logic, the Stockfish engine wrapper, the analysis sweep, history /
// coaching profile, prompt building, and the on-device CoachLLM abstraction.
// The Xcode app targets (GemmaChessiOS / GemmaChessMac) depend on this package
// and hold only UI; see docs/plans for the implementation plan.
let package = Package(
    name: "GemmaChessCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "GemmaChessCore", targets: ["GemmaChessCore"]),
    ],
    dependencies: [
        // python-chess equivalent: FEN/PGN/SAN/UCI, bitboard move-gen, EPD.
        .package(url: "https://github.com/chesskit-app/chesskit-swift.git", from: "0.17.0"),
        // Stockfish 17 compiled from source behind an async/await UCI API (GPLv3).
        .package(url: "https://github.com/chesskit-app/chesskit-engine.git", from: "0.7.0"),
    ],
    targets: [
        .target(
            name: "GemmaChessCore",
            dependencies: [
                .product(name: "ChessKit", package: "chesskit-swift"),
                .product(name: "ChessKitEngine", package: "chesskit-engine"),
            ],
            path: "Sources/GemmaChessCore",
            resources: [
                .copy("Resources/eco"),
                .copy("Resources/nnue"),
            ]
        ),
        .testTarget(
            name: "GemmaChessCoreTests",
            dependencies: ["GemmaChessCore"],
            path: "Tests/GemmaChessCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
