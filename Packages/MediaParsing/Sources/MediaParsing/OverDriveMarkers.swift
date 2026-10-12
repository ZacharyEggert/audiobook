import Foundation

/// Chapters from OverDrive's `TXXX:OverDrive MediaMarkers` XML:
/// `<Markers><Marker><Name>Chapter 1</Name><Time>0:00.000</Time></Marker>…</Markers>`.
/// Scanned with a regex rather than XMLParser, which needs FoundationXML on Linux.
enum OverDriveMarkers {
    static func chapters(from xml: String) -> [RawChapter] {
        let marker = /<Marker>\s*<Name>(.*?)<\/Name>\s*<Time>(.*?)<\/Time>/.dotMatchesNewlines()
        return xml.matches(of: marker).compactMap { match in
            clockSeconds(match.output.2.trimmingCharacters(in: .whitespaces)).map {
                RawChapter(start: $0, title: unescape(String(match.output.1)).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
    }

    private static func unescape(_ text: String) -> String {
        [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")]
            .reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}
