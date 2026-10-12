import Foundation

public struct CueSheet: Equatable, Sendable {
    public struct File: Equatable, Sendable {
        /// As written in the sheet, relative to the sheet's folder.
        public var name: String
        /// One per `TRACK` with an `INDEX 01`, relative to the start of this file.
        public var chapters: [RawChapter]
    }

    /// Disc-level `TITLE`/`PERFORMER` (before the first `TRACK`).
    public var title: String?
    public var performer: String?
    public var files: [File] = []
}

/// Parses CUE sheets leniently: unknown or malformed lines are skipped, never fatal.
public enum CueParser {
    /// Decodes UTF-8 (BOM optional), falling back to Windows-1252, which older rippers wrote.
    public static func parse(_ data: Data) -> CueSheet {
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252) ?? data.latin1
        return parse(text)
    }

    public static func parse(_ text: String) -> CueSheet {
        var sheet = CueSheet()
        var inTrack = false
        var trackTitle = ""
        for line in text.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces.union(["\u{FEFF}"]))
            let command = trimmed.prefix { !$0.isWhitespace }.uppercased()
            let argument = trimmed.dropFirst(command.count).trimmingCharacters(in: .whitespaces)
            switch command {
            case "FILE":
                sheet.files.append(CueSheet.File(name: firstValue(argument), chapters: []))
                inTrack = false
            case "TRACK":
                inTrack = true
                trackTitle = ""
            case "TITLE" where inTrack:
                trackTitle = firstValue(argument)
            case "TITLE":
                sheet.title = firstValue(argument)
            case "PERFORMER" where !inTrack:
                sheet.performer = firstValue(argument)
            case "INDEX" where inTrack && !sheet.files.isEmpty:
                let parts = argument.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count == 2, Int(parts[0]) == 1, let start = seconds(parts[1]) else { continue }
                sheet.files[sheet.files.count - 1].chapters.append(RawChapter(start: start, title: trackTitle))
            default: break
            }
        }
        return sheet
    }

    /// The quoted string, or the first word when unquoted (`FILE book.mp3 MP3`).
    private static func firstValue(_ argument: String) -> String {
        if argument.hasPrefix("\""), let close = argument.dropFirst().firstIndex(of: "\"") {
            return String(argument[argument.index(after: argument.startIndex) ..< close])
        }
        if argument.hasPrefix("\"") {
            return String(argument.dropFirst()) // unterminated quote: take the rest
        }
        return String(argument.prefix { !$0.isWhitespace })
    }

    /// `MM:SS:FF`, with 75 frames per second. Minutes may exceed 99.
    private static func seconds(_ time: Substring) -> TimeInterval? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 >= 0 }), parts[1] < 60, parts[2] < 75 else { return nil }
        return TimeInterval(parts[0] * 60 + parts[1]) + TimeInterval(parts[2]) / 75
    }
}
