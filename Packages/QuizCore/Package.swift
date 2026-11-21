// swift-tools-version: 6.0
// QuizCore: pure-Swift game logic for BuckleUp Quiz.
// No UIKit/AVFoundation imports allowed here, so it builds and tests on Linux (see ADR-0003).
import PackageDescription

let package = Package(
    name: "QuizCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QuizCore", targets: ["QuizCore"])
    ],
    targets: [
        .target(name: "QuizCore"),
        .testTarget(
            name: "QuizCoreTests",
            dependencies: ["QuizCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
