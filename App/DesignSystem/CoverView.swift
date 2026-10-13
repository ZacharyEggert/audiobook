import Library
import SwiftUI
import UIKit

/// A book's cover, square, loaded off the main thread from `CoverStore`'s cache, with a generated placeholder
/// until then or when there is none (PLAN §6).
struct CoverView: View {
    let bookID: UUID
    let coverRef: String?
    let title: String
    var size: CoverStore.Size = .list
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    CoverPlaceholder(title: title)
                }
            }
            .clipShape(.rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
            .accessibilityHidden(true)
            .task(id: "\(bookID)\(coverRef ?? "")\(size)") {
                image = await CoverCache.image(bookID: bookID, coverRef: coverRef, size: size)
            }
    }
}

/// Decoded covers in memory, over `CoverStore`'s disk cache.
enum CoverCache {
    static let store = CoverStore()
    private static let memory = NSCache<NSString, UIImage>()

    static func image(bookID: UUID, coverRef: String?, size: CoverStore.Size) async -> UIImage? {
        guard let coverRef else { return nil }
        let key = "\(bookID)-\(size)-\(coverRef)" as NSString
        if let cached = memory.object(forKey: key) {
            return cached
        }
        guard let url = await store.thumbnail(bookID: bookID, coverRef: coverRef, size: size),
              let image = await decode(url)
        else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    /// Drops a book's covers from memory and disk.
    static func remove(bookID: UUID) {
        memory.removeAllObjects() // ponytail: NSCache can't drop by prefix; covers reload from disk cheaply
        store.removeCache(for: bookID)
    }

    @concurrent private static func decode(_ url: URL) async -> UIImage? {
        await UIImage(contentsOfFile: url.path)?.byPreparingForDisplay()
    }
}

/// The title on a navy gradient whose shade comes from a hash of the title, so each book keeps its look.
struct CoverPlaceholder: View {
    let title: String

    var body: some View {
        let hash = title.unicodeScalars.reduce(UInt32(2_166_136_261)) { ($0 ^ $1.value) &* 16_777_619 } // FNV-1a
        let hue = 0.58 + Double(hash % 64) / 64 * 0.08 // 209°–238°, all navy
        let angle = Double((hash >> 8) % 360) * .pi / 180
        LinearGradient(
            colors: [Color(hue: hue, saturation: 0.75, brightness: 0.28), Color(hue: hue + 0.02, saturation: 0.6, brightness: 0.5)],
            startPoint: UnitPoint(x: 0.5 - cos(angle) / 2, y: 0.5 - sin(angle) / 2),
            endPoint: UnitPoint(x: 0.5 + cos(angle) / 2, y: 0.5 + sin(angle) / 2),
        )
        .overlay {
            GeometryReader { proxy in
                Text(title)
                    .font(.system(size: max(proxy.size.width / 8, 6), weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .padding(proxy.size.width / 10)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
    }
}

#Preview {
    HStack {
        ForEach(["Dune", "The Hobbit", "Project Hail Mary"], id: \.self) {
            CoverView(bookID: UUID(), coverRef: nil, title: $0).frame(width: 110)
        }
    }
    .padding()
}
