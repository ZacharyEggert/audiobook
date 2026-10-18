@testable import EarReader
import Foundation
import Library
import Playback
import SwiftData
import Testing

@MainActor struct ListeningLogTests {
    let container = try! LibraryStore.makeContainer(directory: nil) // swiftlint:disable:this force_try
    let bookID = UUID()

    var context: ModelContext {
        container.mainContext
    }

    private func sample(id: UUID = UUID(), real: TimeInterval, content: TimeInterval) -> ListeningSample {
        ListeningSample(id: id, bookID: bookID, start: Date(timeIntervalSince1970: 100), real: real, content: content)
    }

    private func records() -> [ListeningSessionRecord] {
        (try? context.fetch(FetchDescriptor<ListeningSessionRecord>())) ?? []
    }

    @Test func `a growing session updates one record`() {
        let id = UUID()
        ListeningLog.record(sample(id: id, real: 5, content: 7), in: context)
        ListeningLog.record(sample(id: id, real: 10, content: 15), in: context)
        let stored = records()
        #expect(stored.count == 1)
        #expect(stored.first?.realSeconds == 10)
        #expect(stored.first?.contentSeconds == 15)
        #expect(stored.first?.bookID == bookID)
    }

    @Test func `separate sessions get separate records`() {
        ListeningLog.record(sample(real: 5, content: 5), in: context)
        ListeningLog.record(sample(real: 5, content: 5), in: context)
        #expect(records().count == 2)
    }

    @Test func `taps shorter than a second are not logged`() {
        ListeningLog.record(sample(real: 0.4, content: 0.4), in: context)
        #expect(records().isEmpty)
    }

    @Test func `records become stats entries`() {
        ListeningLog.record(sample(real: 60, content: 90), in: context)
        let entry = records().entries.first
        #expect(entry?.real == 60)
        #expect(entry?.content == 90)
        #expect(entry?.start == Date(timeIntervalSince1970: 100))
    }
}
