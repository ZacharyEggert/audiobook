// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Playback",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "Playback", targets: ["Playback"])],
    targets: [
        .target(name: "Playback"),
        .testTarget(name: "PlaybackTests", dependencies: ["Playback"]),
    ],
)
