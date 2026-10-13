import AudiobookCore
import Foundation
import SwiftData

/// Version 1 of the library store. To change a model, copy it into a `LibrarySchemaV2`, point the typealiases there,
/// and add a stage to `LibraryMigrationPlan`.
public enum LibrarySchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version {
        Schema.Version(1, 0, 0)
    }

    public static var models: [any PersistentModel.Type] {
        localModels + syncedModels
    }

    /// Stay on this device: what was imported and read from the audio.
    public static var localModels: [any PersistentModel.Type] {
        [BookRecord.self, FileRecord.self, ChapterRecord.self, MetadataOverride.self]
    }

    /// Mirrored to iCloud from M6, so they follow CloudKit's rules: no unique attributes, every property optional or
    /// defaulted, and no relationships to local models (they name books by `bookID`, which also lets them outlive the audio).
    public static var syncedModels: [any PersistentModel.Type] {
        [ProgressRecord.self, BookmarkRecord.self, CollectionRecord.self]
    }

    @Model public final class BookRecord {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var authors: [String]
        public var narrators: [String]
        public var series: String?
        public var seriesIndex: Double?
        public var summary: String?
        public var year: Int?
        public var genre: String?
        public var publisher: String?
        /// Relative to the library folder.
        public var coverRef: String?
        public var duration: TimeInterval
        public var dateAdded: Date
        /// Album or artist tags disagreed at import, so the grouping may be wrong.
        public var needsReview: Bool
        /// Unordered; see `orderedFiles`.
        @Relationship(deleteRule: .cascade, inverse: \FileRecord.book) public var files: [FileRecord] = []
        /// Unordered; see `orderedChapters`.
        @Relationship(deleteRule: .cascade, inverse: \ChapterRecord.book) public var chapters: [ChapterRecord] = []
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
        public var index: Int
        /// Relative to the book's folder.
        public var relativePath: String
        public var duration: TimeInterval
        public var globalOffset: TimeInterval
        public var format: String
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
        public var index: Int
        public var title: String
        public var start: TimeInterval
        public var end: TimeInterval
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
    /// Local and synced models live in separate stores, so M6 can turn on CloudKit for the synced one alone.
    /// - Parameter directory: Where the two `.store` files go; nil keeps both in memory (tests, previews).
    public static func makeContainer(directory: URL? = .applicationSupportDirectory) throws -> ModelContainer {
        func configuration(_ name: String, _ models: [any PersistentModel.Type]) -> ModelConfiguration {
            let schema = Schema(models)
            guard let directory else {
                return ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: true)
            }
            return ModelConfiguration(name, schema: schema, url: directory.appending(path: "\(name).store"), cloudKitDatabase: .none)
        }
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return try ModelContainer(
            for: Schema(versionedSchema: LibrarySchemaV1.self),
            migrationPlan: LibraryMigrationPlan.self,
            configurations: configuration("Local", LibrarySchemaV1.localModels),
            configuration("Synced", LibrarySchemaV1.syncedModels),
        )
    }
}

public extension BookRecord {
    var orderedFiles: [FileRecord] {
        files.sorted { $0.index < $1.index }
    }

    var orderedChapters: [ChapterRecord] {
        chapters.sorted { $0.index < $1.index }
    }

    /// The book with the user's overrides applied, for playback and display.
    var book: Book {
        Book(
            id: id, title: override?.title ?? title, authors: override?.authors ?? authors,
            narrators: override?.narrators ?? narrators, series: override?.series ?? series,
            seriesIndex: override?.seriesIndex ?? seriesIndex, coverRef: coverRef,
            files: orderedFiles.map { AudioFile(relativePath: $0.relativePath, duration: $0.duration, format: $0.format) },
            chapters: orderedChapters.map { Chapter(index: $0.index, title: $0.title, start: $0.start, end: $0.end) },
        )
    }
}
