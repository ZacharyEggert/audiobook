// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Library",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "Library", targets: ["Library"])],
    dependencies: [.package(path: "../MediaParsing"), .package(path: "../AudiobookCore")],
    targets: [
        .target(name: "Library", dependencies: ["MediaParsing", "AudiobookCore"]),
        .testTarget(name: "LibraryTests", dependencies: ["Library", "AudiobookCore"]),
    ],
)
