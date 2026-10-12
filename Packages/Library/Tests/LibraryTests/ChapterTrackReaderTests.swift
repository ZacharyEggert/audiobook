import Foundation
@testable import Library
import MediaParsing
import Testing

@Test func `reads QuickTime chapter track`() async throws {
    let chapters = try await ChapterTrackReader.chapters(of: fixture("chapters.m4b"))
    #expect(chapters == [
        RawChapter(start: 0, title: "Opening"),
        RawChapter(start: 2, title: "Middle"),
        RawChapter(start: 4.5, title: "Ending"),
    ])
}

@Test func `ignores Nero chpl chapters`() async throws {
    #expect(try await ChapterTrackReader.chapters(of: fixture("nero-chapters.m4b")).isEmpty)
}
