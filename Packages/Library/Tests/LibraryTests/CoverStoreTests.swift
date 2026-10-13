import CoreGraphics
import Foundation
import ImageIO
@testable import Library
import SwiftData
import Testing
import UniformTypeIdentifiers

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "covers-\(UUID())", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A solid PNG of the given pixel size.
private func writePNG(width: Int, height: Int, to url: URL) throws {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ))
    context.setFillColor(red: 0.08, green: 0.16, blue: 0.35, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

private func pixelSize(_ url: URL) throws -> (Int, Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
}

@Test(arguments: CoverStore.Size.allCases)
func `downscales and caches each size`(size: CoverStore.Size) async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let id = UUID()
    try FileManager.default.createDirectory(at: root.appending(path: "Library/\(id)"), withIntermediateDirectories: true)
    try writePNG(width: 2000, height: 1000, to: root.appending(path: "Library/\(id)/cover.png"))
    let store = CoverStore(libraryRoot: root.appending(path: "Library"), cacheRoot: root.appending(path: "Cache"))

    let url = try #require(await store.thumbnail(bookID: id, coverRef: "\(id)/cover.png", size: size))
    let (width, height) = try pixelSize(url)
    #expect(width == size.rawValue && height == size.rawValue / 2)

    let made = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    #expect(await store.thumbnail(bookID: id, coverRef: "\(id)/cover.png", size: size) == url)
    #expect(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == made) // not rebuilt

    store.removeCache(for: id)
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func `no thumbnail without a readable cover`() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = CoverStore(libraryRoot: root, cacheRoot: root.appending(path: "Cache"))
    #expect(await store.thumbnail(bookID: UUID(), coverRef: "missing/cover.jpg", size: .list) == nil)
}

@Test func `prefers named covers, then the largest image`() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder.appending(path: "CD1"), withIntermediateDirectories: true)
    try Data(count: 10).write(to: folder.appending(path: "CD1/Cover.JPG"))
    try Data(count: 10).write(to: folder.appending(path: "folder.jpg"))
    try Data(count: 99).write(to: folder.appending(path: "back.png"))

    #expect(CoverStore.saveCover(embedded: nil, images: ["back.png", "folder.jpg", "CD1/Cover.JPG"], in: folder) == "CD1/Cover.JPG")
    #expect(CoverStore.saveCover(embedded: nil, images: ["back.png", "folder.jpg"], in: folder) == "folder.jpg")
    #expect(CoverStore.saveCover(embedded: nil, images: ["back.png", "CD1/other.jpg"], in: folder) == "back.png")
    #expect(CoverStore.saveCover(embedded: Data("not an image".utf8), images: [], in: folder) == nil)
}

@Test(arguments: [("chapters.m4b", "embedded-cover.jpg"), ("multi-mp3", "cover.jpg")])
func `import records the cover`(item: String, cover: String) async throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "library-\(UUID())", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let container = try LibraryStore.makeContainer(directory: nil)
    let importer = LibraryImporter(modelContainer: container, root: root, availableCapacity: { _ in .max })
    let id = try #require(try await importer.importItems([fixture(item)]).bookIDs.first)

    let book = try #require(try ModelContext(container).fetch(FetchDescriptor<BookRecord>()).first)
    #expect(book.coverRef == "\(id)/\(cover)")
    let store = CoverStore(libraryRoot: root, cacheRoot: root.appending(path: ".covers"))
    #expect(try await store.thumbnail(bookID: id, coverRef: #require(book.coverRef), size: .list) != nil)
}
