import Foundation

/// Audio we recognise but can't import, with a reason to show the user.
public enum UnsupportedFormat: Error, Equatable, Sendable {
    case audible
    case oggVorbis
    case opus
    case wma

    public var reason: String {
        switch self {
        case .audible: "Audible AAX and AAXC files are DRM-protected. Ear Reader plays DRM-free audiobooks only."
        case .oggVorbis: "Ogg Vorbis files aren't supported yet."
        case .opus: "Opus files aren't supported yet."
        case .wma: "Windows Media Audio (WMA) files aren't supported."
        }
    }

    /// Checks the signature, plus the extension for Audible (whose files are otherwise MP4).
    /// ponytail: FairPlay-protected iTunes .m4b (`drms` sample entry) isn't detected; it would fail at playback.
    static func detect(_ data: Data, pathExtension: String) -> UnsupportedFormat? {
        let head = Data(data.prefix(64))
        if ["aax", "aaxc"].contains(pathExtension.lowercased()) || (head.count >= 12 && Data(head[4 ..< 11]).latin1 == "ftypaax") {
            return .audible
        }
        if head.starts(with: Data("OggS".utf8)) {
            // The first page's packet names the codec; byte 26 is the segment count, then the segment table
            let packetStart = head.count > 26 ? 27 + Int(head[26]) : head.count
            return head.dropFirst(packetStart).starts(with: Data("OpusHead".utf8)) ? .opus : .oggVorbis
        }
        if head.starts(with: [0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C]) {
            return .wma // ASF header object GUID
        }
        return nil
    }
}
