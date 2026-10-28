import AppKit
import Foundation

@main struct GIFClipboardTest {
  static let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!

  static func item() -> GIFItem {
    GIFItem(id: "g1", title: "Pixel",
            thumbnailURL: URL(string: "https://cdn.example/thumb.gif")!,
            gifURL: URL(string: "https://cdn.example/full.gif")!,
            sourceURL: URL(string: "https://example.com/pixel")!,
            width: 1, height: 1, provider: .custom)
  }

  @MainActor static func main() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("rime-gif-clipboard-\(UUID().uuidString)", isDirectory: true)
    let pasteboard = NSPasteboard(name: .init("im.rime.test.gif.\(UUID().uuidString)"))
    defer { try? FileManager.default.removeItem(at: directory) }

    let response = HTTPURLResponse(url: item().gifURL, statusCode: 200, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": "image/gif"])!
    let fileURL = try await GIFClipboard.copy(
      item: item(),
      downloader: { _ in (gif, response) },
      pasteboard: pasteboard,
      cacheDirectory: directory
    )
    precondition(fileURL.path.hasPrefix(directory.path))
    precondition(fileURL.pathExtension == "gif")
    let saved = try Data(contentsOf: fileURL)
    precondition(saved == gif)
    let directoryMode = (try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue
    let fileMode = (try FileManager.default.attributesOfItem(atPath: fileURL.path)[.posixPermissions] as? NSNumber)?.intValue
    precondition(directoryMode == 0o700, "cache directory must be private: \(String(directoryMode ?? -1, radix: 8))")
    precondition(fileMode == 0o600, "cached GIF must be private: \(String(fileMode ?? -1, radix: 8))")

    let written = pasteboard.pasteboardItems?.first
    precondition(written?.data(forType: GIFClipboard.gifType) == gif)
    precondition(written?.string(forType: .fileURL) == fileURL.absoluteString)
    precondition(written?.string(forType: .URL) == "https://example.com/pixel")
    precondition(!(written?.data(forType: .tiff)?.isEmpty ?? true))
    precondition(!(written?.data(forType: .png)?.isEmpty ?? true))

    // Same bytes reuse the same content-addressed file.
    let again = try GIFClipboard.writeCache(data: gif, directory: directory)
    precondition(again == fileURL)

    do {
      _ = try await GIFClipboard.copy(item: item(),
        downloader: { _ in (Data("not a gif".utf8), response) },
        pasteboard: pasteboard, cacheDirectory: directory)
      preconditionFailure("non-GIF bytes must be rejected")
    } catch let error as GIFClipboardError {
      guard case .notGIF = error else { preconditionFailure("wrong error: \(error)") }
    }

    let html = HTTPURLResponse(url: item().gifURL, statusCode: 200, httpVersion: "HTTP/1.1",
                               headerFields: ["Content-Type": "text/html"])!
    do {
      _ = try await GIFClipboard.copy(item: item(),
        downloader: { _ in (gif, html) },
        pasteboard: pasteboard, cacheDirectory: directory)
      preconditionFailure("HTML content type must be rejected")
    } catch let error as GIFClipboardError {
      guard case .notGIF = error else { preconditionFailure("wrong error: \(error)") }
    }

    let failure = HTTPURLResponse(url: item().gifURL, statusCode: 404, httpVersion: "HTTP/1.1",
                                  headerFields: ["Content-Type": "image/gif"])!
    do {
      _ = try await GIFClipboard.copy(item: item(),
        downloader: { _ in (gif, failure) },
        pasteboard: pasteboard, cacheDirectory: directory)
      preconditionFailure("HTTP 404 must be rejected")
    } catch let error as GIFClipboardError {
      guard case .http(404) = error else { preconditionFailure("wrong error: \(error)") }
    }

    // Cache housekeeping removes old files, then trims by size.
    let cleanupDir = directory.appendingPathComponent("cleanup", isDirectory: true)
    try FileManager.default.createDirectory(at: cleanupDir, withIntermediateDirectories: true)
    let old = cleanupDir.appendingPathComponent("old.gif")
    let recent = cleanupDir.appendingPathComponent("recent.gif")
    try Data(repeating: 1, count: 10).write(to: old)
    try Data(repeating: 2, count: 10).write(to: recent)
    let now = Date()
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-8 * 86400)], ofItemAtPath: old.path)
    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: recent.path)
    let removed = GIFClipboard.cleanup(directory: cleanupDir, maxAge: 7 * 86400,
                                       maxBytes: 100 * 1024 * 1024, now: now)
    precondition(removed == 1 && !FileManager.default.fileExists(atPath: old.path))
    precondition(FileManager.default.fileExists(atPath: recent.path))
    let trimmed = GIFClipboard.cleanup(directory: cleanupDir, maxAge: 7 * 86400,
                                       maxBytes: 1, now: now)
    precondition(trimmed == 1 && !FileManager.default.fileExists(atPath: recent.path))

    print("PASS: downloads and validates GIF magic/content type; private atomic cache; GIF/fileURL/TIFF/PNG/source pasteboard types; failures retain; old cache trimmed")
  }
}
