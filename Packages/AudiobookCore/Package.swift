// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AudiobookCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "AudiobookCore", targets: ["AudiobookCore"])],
    targets: [
        .target(name: "AudiobookCore"),
        .testTarget(name: "AudiobookCoreTests", dependencies: ["AudiobookCore"]),
    ],
)
