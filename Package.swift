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
    targets: [
        .target(
            name: "GemmaChessCore",
            path: "Sources/GemmaChessCore"
        ),
        .testTarget(
            name: "GemmaChessCoreTests",
            dependencies: ["GemmaChessCore"],
            path: "Tests/GemmaChessCoreTests"
        ),
    ]
)
