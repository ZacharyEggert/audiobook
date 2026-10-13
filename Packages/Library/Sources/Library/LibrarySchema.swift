import AudiobookCore
import Foundation
import SwiftData

/// Version 1 of the library store. To change a model, copy it into a `LibrarySchemaV2`, point the typealiases there,
/// and add a stage to `LibraryMigrationPlan`.
///
/// The whole library mirrors to iCloud from M6 (the audio itself syncs through iCloud Drive), so every model follows
/// CloudKit's rules: no unique attributes, every property optional or defaulted, every relationship optional.
/// Progress, bookmarks and collections name books by `bookID` rather than a relationship, so they outlive a book's audio.
public enum LibrarySchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        [
            BookRecord.self, FileRecord.self, ChapterRecord.self, MetadataOverride.self,
            ProgressRecord.self, BookmarkRecord.self, CollectionRecord.self,
        ]
    }

    @Model public final class BookRecord {
        /// Also names the book's folder in the library, on every device.
        public var id = UUID()
        public var title = ""
        public var authors: [String] = []
        public var narrators: [String] = []
        public var series: String?
        public var seriesIndex: Double?
        public var summary: String?
        public var year: Int?
        public var genre: String?
        public var publisher: String?
        /// Relative to the library folder.
        public var coverRef: String?
        public var duration: TimeInterval = 0
        public var dateAdded = Date.distantPast
        /// Album or artist tags disagreed at import, so the grouping may be wrong.
        public var needsReview = false
        /// Unordered; see `orderedFiles`. Optional, as CloudKit requires.
        @Relationship(deleteRule: .cascade, inverse: \FileRecord.book) public var files: [FileRecord]? = []
        /// Unordered; see `orderedChapters`.
        @Relationship(deleteRule: .cascade, inverse: \ChapterRecord.book) public var chapters: [ChapterRecord]? = []
        /// The user's edits, kept apart so a re-scan doesn't overwrite them.
        @Relationship(deleteRule: .cascade, inverse: \MetadataOverride.book) public var override: MetadataOverride?

        public init(
            id: UUID = UUID(), title: String, authors: [String] = [], narrators: [String] = [], series: String? = nil,
            seriesIndex: Double? = nil, summary: String? = nil, year: Int? = nil, genre: String? = nil, publisher: String? = nil,
            coverRef: String? = nil, duration: TimeInterval = 0, dateAdded: Date = .now, needsReview: Bool = false,
        ) {
            self.id = id
            self.title = title
            self.authors = authors
            self.narrators = narrators
            self.series = series
            self.seriesIndex = seriesIndex
            self.summary = summary
            self.year = year
            self.genre = genre
            self.publisher = publisher
            self.coverRef = coverRef
            self.duration = duration
            self.dateAdded = dateAdded
            self.needsReview = needsReview
        }
    }

    @Model public final class FileRecord {
        public var index = 0
        /// Relative to the book's folder.
        public var relativePath = ""
        public var duration: TimeInterval = 0
        public var globalOffset: TimeInterval = 0
        public var format = ""
        public var book: BookRecord?

        public init(index: Int, relativePath: String, duration: TimeInterval, globalOffset: TimeInterval, format: String) {
            self.index = index
            self.relativePath = relativePath
            self.duration = duration
            self.globalOffset = globalOffset
            self.format = format
        }
    }

    @Model public final class ChapterRecord {
        public var index = 0
        public var title = ""
        public var start: TimeInterval = 0
        public var end: TimeInterval = 0
        public var book: BookRecord?

        public init(index: Int, title: String, start: TimeInterval, end: TimeInterval) {
            self.index = index
            self.title = title
            self.start = start
            self.end = end
        }
    }

    /// Fields the user edited. Nil means "use what the files say".
    @Model public final class MetadataOverride {
        public var title: String?
        public var authors: [String]?
        public var narrators: [String]?
        public var series: String?
        public var seriesIndex: Double?
        public var summary: String?
        public var book: BookRecord?

        public init(
            title: String? = nil, authors: [String]? = nil, narrators: [String]? = nil, series: String? = nil,
            seriesIndex: Double? = nil, summary: String? = nil,
        ) {
            self.title = title
            self.authors = authors
            self.narrators = narrators
            self.series = series
            self.seriesIndex = seriesIndex
            self.summary = summary
        }
    }

    /// Where the listener is in one book. One per book; the newest `updatedAt` wins when devices disagree.
    @Model public final class ProgressRecord {
        public var bookID = UUID()
        /// Global book seconds.
        public var position: TimeInterval = 0
        public var isFinished = false
        public var updatedAt = Date.distantPast

        public init(bookID: UUID, position: TimeInterval = 0, isFinished: Bool = false, updatedAt: Date = .now) {
            self.bookID = bookID
            self.position = position
            self.isFinished = isFinished
            self.updatedAt = updatedAt
        }
    }

    @Model public final class BookmarkRecord {
        public var id = UUID()
        public var bookID = UUID()
        /// Global book seconds.
        public var position: TimeInterval = 0
        public var note: String?
        public var createdAt = Date.distantPast

        public init(id: UUID = UUID(), bookID: UUID, position: TimeInterval, note: String? = nil, createdAt: Date = .now) {
            self.id = id
            self.bookID = bookID
            self.position = position
            self.note = note
            self.createdAt = createdAt
        }
    }

    /// A user playlist of books.
    @Model public final class CollectionRecord {
        public var id = UUID()
        public var name = ""
        /// In the user's order.
        public var bookIDs: [UUID] = []
        public var createdAt = Date.distantPast

        public init(id: UUID = UUID(), name: String, bookIDs: [UUID] = [], createdAt: Date = .now) {
            self.id = id
            self.name = name
            self.bookIDs = bookIDs
            self.createdAt = createdAt
        }
    }
}

public typealias BookRecord = LibrarySchemaV1.BookRecord
public typealias FileRecord = LibrarySchemaV1.FileRecord
public typealias ChapterRecord = LibrarySchemaV1.ChapterRecord
public typealias MetadataOverride = LibrarySchemaV1.MetadataOverride
public typealias ProgressRecord = LibrarySchemaV1.ProgressRecord
public typealias BookmarkRecord = LibrarySchemaV1.BookmarkRecord
public typealias CollectionRecord = LibrarySchemaV1.CollectionRecord

public enum LibraryMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [LibrarySchemaV1.self]
    }

    public static var stages: [MigrationStage] {
        []
    }
}

public enum LibraryStore {
    /// - Parameter directory: Where `Library.store` goes; nil keeps it in memory (tests, previews).
    /// ponytail: `cloudKitDatabase: .none` until M6 adds the iCloud entitlements and switches it to `.private`.
    public static func makeContainer(directory: URL? = .applicationSupportDirectory) throws -> ModelContainer {
        let schema = Schema(versionedSchema: LibrarySchemaV1.self)
        let configuration = if let directory {
            ModelConfiguration("Library", schema: schema, url: directory.appending(path: "Library.store"), cloudKitDatabase: .none)
        } else {
            ModelConfiguration("Library", schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return try ModelContainer(for: schema, migrationPlan: LibraryMigrationPlan.self, configurations: configuration)
    }
}

public extension BookRecord {
    var orderedFiles: [FileRecord] {
        (files ?? []).sorted { $0.index < $1.index }
    }

    var orderedChapters: [ChapterRecord] {
        (chapters ?? []).sorted { $0.index < $1.index }
    }

    /// The user's overrides applied, for display.
    var displayTitle: String {
        override?.title ?? title
    }

    var displayAuthors: [String] {
        override?.authors ?? authors
    }

    var displayNarrators: [String] {
        override?.narrators ?? narrators
    }

    var displaySeries: String? {
        override?.series ?? series
    }

    var displaySeriesIndex: Double? {
        override?.seriesIndex ?? seriesIndex
    }

    var displaySummary: String? {
        override?.summary ?? summary
    }

    /// The book with the user's overrides applied, for playback.
    var book: Book {
        Book(
            id: id, title: displayTitle, authors: displayAuthors, narrators: displayNarrators, series: displaySeries,
            seriesIndex: displaySeriesIndex, coverRef: coverRef,
            files: orderedFiles.map { AudioFile(relativePath: $0.relativePath, duration: $0.duration, format: $0.format) },
            chapters: orderedChapters.map { Chapter(index: $0.index, title: $0.title, start: $0.start, end: $0.end) },
        )
    }
}
