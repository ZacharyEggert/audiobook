import Foundation

/// A probed audio file as grouping sees it.
public struct GroupingFile: Hashable, Sendable {
    /// Relative to the import, with "/" separators: `"Dune/CD1/01.mp3"`, or `"Dune.m4b"` for a file picked on its own.
    public var path: String
    public var album: String?
    public var artist: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var duration: TimeInterval
    public var hasChapters: Bool
    /// An MP4 container (.m4b, .m4a).
    public var isMP4: Bool

    public init(
        path: String, album: String? = nil, artist: String? = nil, trackNumber: Int? = nil, discNumber: Int? = nil,
        duration: TimeInterval = 0, hasChapters: Bool = false, isMP4: Bool = false,
    ) {
        self.path = path
        self.album = album
        self.artist = artist
        self.trackNumber = trackNumber
        self.discNumber = discNumber
        self.duration = duration
        self.hasChapters = hasChapters
        self.isMP4 = isMP4
    }
}

/// Files that make up one book.
public struct BookGroup: Equatable, Sendable {
    /// The folder the files' paths are relative to inside the book ("" for the import's top level).
    public var folder: String
    /// Folder or file name, to title the book when its tags don't.
    public var name: String
    /// In play order.
    public var files: [GroupingFile]
    /// Album or artist tags disagree, so the grouping may be wrong.
    public var needsReview: Bool

    public init(folder: String, name: String, files: [GroupingFile], needsReview: Bool = false) {
        self.folder = folder
        self.name = name
        self.files = files
        self.needsReview = needsReview
    }
}

/// Splits imported files into books (PLAN §3.5).
public enum BookGrouping {
    /// A file this long, or with its own chapters, can be a book by itself.
    public static let standaloneDuration: TimeInterval = 20 * 60

    /// - Each folder's direct audio files form one book; files picked on their own count as one folder.
    /// - `CD1`, `Disc 2`, `Part 03` subfolders merge into their parent, in that number's order.
    /// - A folder of several standalone files (each with chapters, or an MP4 of 20 min or more) gives one book per file,
    ///   unless they share an album and are numbered as parts.
    /// - Files play in disc, then track, then natural filename order.
    public static func group(_ files: [GroupingFile]) -> [BookGroup] {
        var folders: [String: [(file: GroupingFile, discFolder: Int?)]] = [:]
        for file in files {
            var components = file.path.split(separator: "/").map(String.init)
            components.removeLast()
            let discFolder = components.last.flatMap(discNumber)
            if discFolder != nil {
                components.removeLast()
            }
            folders[components.joined(separator: "/"), default: []].append((file, discFolder))
        }

        var groups: [BookGroup] = []
        for folder in folders.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let entries = folders[folder]!
            let ordered = order(entries)
            let hasDiscFolders = entries.contains { $0.discFolder != nil }
            if !hasDiscFolders, ordered.count > 1, ordered.allSatisfy(isStandalone), !areNumberedParts(ordered) {
                groups += ordered.map { BookGroup(folder: folder, name: stem($0.path), files: [$0]) }
            } else {
                let name = folder.split(separator: "/").last.map(String.init) ?? stem(ordered[0].path)
                groups.append(BookGroup(folder: folder, name: name, files: ordered, needsReview: tagsDisagree(ordered)))
            }
        }
        return groups
    }

    /// `"CD1"`, `"Disc 2"`, `"part_03 (bonus)"` → the number. Anchored at the start, so "Dune Part 2" stays a book folder.
    static func discNumber(_ folderName: String) -> Int? {
        guard let match = folderName.firstMatch(of: /^(?i:cd|disc|disk|part)[\s_-]*(\d+)\b/) else { return nil }
        return Int(match.1)
    }

    /// Disc (folder number before tag), then track, then natural path order. Disc or track numbers are only used
    /// when every file has one and they don't repeat, so a half-tagged folder falls back to filenames.
    private static func order(_ entries: [(file: GroupingFile, discFolder: Int?)]) -> [GroupingFile] {
        let discs = entries.map { $0.discFolder ?? $0.file.discNumber }
        let useDiscs = !discs.contains(nil)
        let keys = entries.indices.map { (useDiscs ? discs[$0]! : 0, entries[$0].file.trackNumber) }
        let useTracks = !keys.contains { $0.1 == nil } && Set(keys.map { "\($0.0)/\($0.1!)" }).count == keys.count
        return entries.indices.sorted { lhs, rhs in
            let left = (keys[lhs].0, useTracks ? keys[lhs].1! : 0), right = (keys[rhs].0, useTracks ? keys[rhs].1! : 0)
            if left != right {
                return left < right
            }
            return entries[lhs].file.path.localizedStandardCompare(entries[rhs].file.path) == .orderedAscending
        }.map { entries[$0].file }
    }

    private static func isStandalone(_ file: GroupingFile) -> Bool {
        file.hasChapters || (file.isMP4 && file.duration >= standaloneDuration)
    }

    /// One shared album, and every file has a distinct track or disc number.
    private static func areNumberedParts(_ files: [GroupingFile]) -> Bool {
        let albums = Set(files.map { $0.album.map(normalized) })
        guard albums.count == 1, albums.first! != nil else { return false }
        func distinct(_ numbers: [Int?]) -> Bool {
            !numbers.contains(nil) && Set(numbers).count == numbers.count
        }
        return distinct(files.map(\.trackNumber)) || distinct(files.map(\.discNumber))
    }

    private static func tagsDisagree(_ files: [GroupingFile]) -> Bool {
        Set(files.compactMap { $0.album.map(normalized) }).count > 1 || Set(files.compactMap { $0.artist.map(normalized) }).count > 1
    }

    private static func normalized(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func stem(_ path: String) -> String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return (name as NSString).deletingPathExtension
    }
}
