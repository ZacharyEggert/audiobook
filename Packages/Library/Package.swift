// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Library",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "Library", targets: ["Library"])],
    dependencies: [.package(path: "../MediaParsing")],
    targets: [
        .target(name: "Library", dependencies: ["MediaParsing"]),
        .testTarget(name: "LibraryTests", dependencies: ["Library"]),
    ],
)
