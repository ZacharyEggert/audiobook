import Foundation

/// A file in the repo's `Tests/Fixtures` (built by `scripts/make-fixtures.sh`).
/// SwiftPM can't bundle resources from outside the package, so this walks up from this source file.
func fixtureURL(_ name: String) -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent() // MediaParsingTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // MediaParsing
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()
        .appending(path: "Tests/Fixtures/\(name)")
}

func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: fixtureURL(name), options: .alwaysMapped)
}
