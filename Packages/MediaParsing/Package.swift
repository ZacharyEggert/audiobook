// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MediaParsing",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "MediaParsing", targets: ["MediaParsing"])],
    targets: [
        .target(name: "MediaParsing"),
        .testTarget(name: "MediaParsingTests", dependencies: ["MediaParsing"]),
    ],
)
