import Foundation

/// A file in the repo's `Tests/Fixtures` (built by `scripts/make-fixtures.sh`).
func fixture(_ name: String) -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent() // LibraryTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Library
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()
        .appending(path: "Tests/Fixtures/\(name)")
}
