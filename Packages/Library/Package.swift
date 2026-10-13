// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Library",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "Library", targets: ["Library"])],
    dependencies: [
        .package(path: "../MediaParsing"),
        .package(path: "../AudiobookCore"),
        .package(url: "https://github.com/weichsel/ZIPFoundation", exact: "0.9.20"),
    ],
    targets: [
        .target(name: "Library", dependencies: ["MediaParsing", "AudiobookCore", "ZIPFoundation"]),
        .testTarget(name: "LibraryTests", dependencies: ["Library", "AudiobookCore", "ZIPFoundation"]),
    ],
)
