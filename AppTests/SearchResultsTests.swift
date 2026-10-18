@testable import EarReader
import Foundation
import Library
import SwiftData
import Testing

@MainActor struct SearchResultsTests {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    let books: [BookRecord]

    init() {
        let dune = BookRecord(
            title: "Dune", authors: ["Frank Herbert"], narrators: ["Scott Brick", "Orlagh Cassidy"], series: "Dune Chronicles",
            seriesIndex: 1,
        )
        let messiah = BookRecord(
            title: "Dune Messiah",
            authors: ["Frank Herbert"],
            narrators: ["Scott Brick"],
            series: "Dune Chronicles",
            seriesIndex: 2,
        )
        let emma = BookRecord(title: "Émma", authors: ["Jane Austen"])
        for (index, title) in ["Book One: Dune", "Litany Against Fear"].enumerated() {
            let chapter = ChapterRecord(index: index, title: title, start: Double(index) * 100, end: Double(index + 1) * 100)
            dune.chapters = (dune.chapters ?? []) + [chapter]
        }
        messiah.chapters = [ChapterRecord(index: 0, title: "Prologue", start: 0, end: 50)]
        books = [dune, messiah, emma]
        books.forEach(container.mainContext.insert)
    }

    @Test func `blank query matches nothing`() {
        #expect(SearchResults(query: "  ", books: books).isEmpty)
    }

    @Test func `matches titles sorted`() {
        let results = SearchResults(query: "dune", books: books)
        #expect(results.titles.map(\.displayTitle) == ["Dune", "Dune Messiah"])
    }

    @Test func `groups authors narrators and series with counts`() {
        #expect(SearchResults(query: "herbert", books: books).authors.map(\.count) == [2])
        #expect(SearchResults(query: "brick", books: books).narrators.map(\.count) == [2])
        let series = SearchResults(query: "chronicles", books: books).series
        #expect(series.map(\.name) == ["Dune Chronicles"])
        #expect(series.first?.kind == .series)
    }

    @Test func `matching a narrator does not list the other narrator`() {
        #expect(SearchResults(query: "cassidy", books: books).narrators.map(\.name) == ["Orlagh Cassidy"])
    }

    @Test func `chapter hit carries its book and start`() throws {
        let hit = try #require(SearchResults(query: "litany", books: books).chapters.first)
        #expect(hit.book.displayTitle == "Dune")
        #expect(hit.chapter.start == 100)
    }

    @Test func `ignores case and diacritics`() {
        #expect(SearchResults(query: "emma", books: books).titles.map(\.displayTitle) == ["Émma"])
    }

    @Test func `uses overrides`() {
        books[2].override = MetadataOverride(title: "Persuasion")
        #expect(SearchResults(query: "persuasion", books: books).titles.count == 1)
        #expect(SearchResults(query: "emma", books: books).titles.isEmpty)
    }

    @Test func `no match is empty`() {
        #expect(SearchResults(query: "zzz", books: books).isEmpty)
    }
}
