import Foundation

/// Loads a file from the repo's `Tests/Fixtures` (built by `scripts/make-fixtures.sh`).
/// SwiftPM can't bundle resources from outside the package, so this walks up from this source file.
func fixture(_ name: String) throws -> Data {
    let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // MediaParsingTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // MediaParsing
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()
    return try Data(contentsOf: root.appending(path: "Tests/Fixtures/\(name)"), options: .alwaysMapped)
}
