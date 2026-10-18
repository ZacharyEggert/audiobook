@testable import EarReader
import Foundation
import Library
import SwiftData
import Testing

@MainActor struct HomeRowsTests {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    var books: [BookRecord] = []
    var progress: [UUID: ProgressRecord] = [:]

    mutating func add(
        _ title: String,
        series: String? = nil,
        index: Double? = nil,
        added: Double = 0,
        position: TimeInterval = 0,
        finished: Bool = false,
        played: Double = 0,
    ) {
        let book = BookRecord(
            title: title,
            series: series,
            seriesIndex: index,
            duration: 100,
            dateAdded: .init(timeIntervalSince1970: added),
        )
        container.mainContext.insert(book)
        books.append(book)
        if position > 0 || finished {
            progress[book.id] = ProgressRecord(
                bookID: book.id,
                position: position,
                isFinished: finished,
                updatedAt: .init(timeIntervalSince1970: played),
            )
        }
    }

    func titles(_ books: [BookRecord]) -> [String] {
        books.map(\.displayTitle)
    }

    @Test func `hero is the latest in progress and leaves the in progress row`() {
        var test = self
        test.add("Old", position: 10, played: 1)
        test.add("New", position: 10, played: 2)
        test.add("Mid", position: 10, played: 1.5)
        let rows = HomeRows(books: test.books, progress: test.progress)
        #expect(rows.hero?.displayTitle == "New")
        #expect(test.titles(rows.inProgress) == ["Mid", "Old"])
    }

    @Test func `recently added is newest first and capped`() {
        var test = self
        for index in 0 ..< 12 {
            test.add("B\(index)", added: Double(index))
        }
        let rows = HomeRows(books: test.books, progress: test.progress)
        #expect(rows.recentlyAdded.count == HomeRows.limit)
        #expect(rows.recentlyAdded.first?.displayTitle == "B11")
        #expect(rows.hero == nil)
    }

    @Test func `finished recently excludes unfinished`() {
        var test = self
        test.add("A", finished: true, played: 1)
        test.add("B", finished: true, played: 2)
        test.add("C", position: 5, played: 3)
        let rows = HomeRows(books: test.books, progress: test.progress)
        #expect(test.titles(rows.finishedRecently) == ["B", "A"])
    }

    @Test func `next in series follows the last finished unstarted book`() {
        var test = self
        test.add("S1", series: "S", index: 1, finished: true, played: 1)
        test.add("S2", series: "S", index: 2, finished: true, played: 2)
        test.add("S3", series: "S", index: 3)
        test.add("S4", series: "S", index: 4)
        test.add("T1", series: "T", index: 1, finished: true, played: 3)
        test.add("T2", series: "T", index: 2, position: 5, played: 4) // already started
        test.add("Solo")
        let rows = HomeRows(books: test.books, progress: test.progress)
        #expect(test.titles(rows.nextInSeries) == ["S3"])
    }

    @Test func `empty library is empty`() {
        #expect(HomeRows(books: [], progress: [:]).isEmpty)
    }
}
