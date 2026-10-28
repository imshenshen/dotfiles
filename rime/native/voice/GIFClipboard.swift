import AppKit
import CryptoKit
import ImageIO

enum GIFClipboardError: LocalizedError {
  case unsafeURL
  case http(Int)
  case tooLarge
  case notGIF
  case invalidImage
  case storage
  case transport

  var errorDescription: String? {
    switch self {
    case .unsafeURL: return "GIF 链接不安全，已停止下载。"
    case .http(let code): return "下载 GIF 失败（HTTP \(code)）。"
    case .tooLarge: return "GIF 超过 20 MB，未复制。"
    case .notGIF: return "下载的内容不是有效 GIF。"
    case .invalidImage: return "无法读取 GIF 首帧。"
    case .storage: return "无法写入 GIF 缓存。"
    case .transport: return "GIF 下载失败或超时。"
    }
  }
}

enum GIFClipboard {
  static let maxBytes = 20_000_000
  static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")
  typealias Downloader = (URL) async throws -> (Data, HTTPURLResponse?)

  static var defaultCacheDirectory: URL {
    let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? FileManager.default.temporaryDirectory
    return base.appendingPathComponent("im.rime.inputmethod.Squirrel/GIFSearch", isDirectory: true)
  }

  @MainActor
  static func copy(item: GIFItem, downloader: Downloader? = nil,
                   pasteboard: NSPasteboard = .general, cacheDirectory: URL? = nil) async throws -> URL {
    guard GIFSearchService.isSafeMedia(item.gifURL, provider: item.provider) else { throw GIFClipboardError.unsafeURL }
    let data: Data
    if let downloader {
      let (downloaded, response) = try await downloader(item.gifURL)
      try validate(data: downloaded, response: response)
      data = downloaded
    } else {
      data = try await download(item.gifURL)
    }
    // Closing the palette cancels this task; never touch the shared clipboard
    // after the user has dismissed the panel.
    try Task.checkCancellation()
    guard let firstFrame = GIFImageDecoder.firstFrame(data, maxPixel: 1200) else {
      throw GIFClipboardError.invalidImage
    }
    try Task.checkCancellation()
    let directory = cacheDirectory ?? defaultCacheDirectory
    let fileURL = try writeCache(data: data, directory: directory)
    guard writePasteboard(data: data, frame: firstFrame, fileURL: fileURL,
                          sourceURL: item.sourceURL ?? item.gifURL, pasteboard: pasteboard) else {
      throw GIFClipboardError.storage
    }
    return fileURL
  }

  static func download(_ url: URL) async throws -> Data {
    guard GIFSearchService.isSafeHTTPS(url) else { throw GIFClipboardError.unsafeURL }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 40
    configuration.urlCache = nil; configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    let session = URLSession(configuration: configuration, delegate: GIFDownloadNoRedirect(), delegateQueue: nil)
    defer { session.finishTasksAndInvalidate() }
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue("image/gif,image/*;q=0.8", forHTTPHeaderField: "Accept")
    request.setValue("RimeGIFSearch/1.0", forHTTPHeaderField: "User-Agent")
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw GIFClipboardError.transport
    }
    try validate(data: data, response: response as? HTTPURLResponse)
    return data
  }

  static func validate(data: Data, response: HTTPURLResponse?) throws {
    if let response {
      guard (200..<300).contains(response.statusCode) else { throw GIFClipboardError.http(response.statusCode) }
      if response.expectedContentLength > Int64(maxBytes) { throw GIFClipboardError.tooLarge }
      if let mime = response.mimeType?.lowercased(), !mime.isEmpty,
         mime != "image/gif", mime != "application/octet-stream" {
        throw GIFClipboardError.notGIF
      }
    }
    guard data.count <= maxBytes else { throw GIFClipboardError.tooLarge }
    guard data.count >= 6, data[0...2] == Data("GIF".utf8),
          data[3...5] == Data("87a".utf8) || data[3...5] == Data("89a".utf8) else {
      throw GIFClipboardError.notGIF
    }
  }

  static func writeCache(data: Data, directory: URL) throws -> URL {
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                             attributes: [.posixPermissions: 0o700])
      try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      let name = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".gif"
      let final = directory.appendingPathComponent(name)
      if fm.fileExists(atPath: final.path) {
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: final.path)
        return final
      }
      let temp = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
      guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
        throw GIFClipboardError.storage
      }
      do {
        try fm.moveItem(at: temp, to: final)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: final.path)
      } catch {
        try? fm.removeItem(at: temp)
        throw GIFClipboardError.storage
      }
      return final
    } catch let error as GIFClipboardError { throw error }
    catch { throw GIFClipboardError.storage }
  }

  @MainActor
  static func pasteboardItem(data: Data, frame: CGImage?, fileURL: URL,
                             sourceURL: URL?) -> NSPasteboardItem {
    let item = NSPasteboardItem()
    item.setString(fileURL.absoluteString, forType: .fileURL)
    item.setData(data, forType: gifType)
    if let frame {
      let rep = NSBitmapImageRep(cgImage: frame)
      if let tiff = rep.representation(using: .tiff, properties: [:]) { item.setData(tiff, forType: .tiff) }
      if let png = rep.representation(using: .png, properties: [:]) { item.setData(png, forType: .png) }
    }
    if let sourceURL { item.setString(sourceURL.absoluteString, forType: .URL) }
    return item
  }

  @MainActor
  @discardableResult
  static func writePasteboard(data: Data, frame: CGImage?, fileURL: URL,
                              sourceURL: URL?, pasteboard: NSPasteboard) -> Bool {
    let item = pasteboardItem(data: data, frame: frame, fileURL: fileURL, sourceURL: sourceURL)
    pasteboard.clearContents()
    return pasteboard.writeObjects([item])
  }

  // Keep the shared cache bounded without touching files outside ours.
  @discardableResult
  static func cleanup(directory: URL = defaultCacheDirectory, maxAge: TimeInterval = 7 * 86400,
                      maxBytes: Int64 = 100 * 1024 * 1024, now: Date = Date()) -> Int {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys:
      [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles]) else { return 0 }
    struct Entry { let url: URL; let date: Date; let size: Int64 }
    var entries = files.compactMap { url -> Entry? in
      guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
            values.isRegularFile == true else { return nil }
      return Entry(url: url, date: values.contentModificationDate ?? .distantPast, size: Int64(values.fileSize ?? 0))
    }
    var removed = 0
    for entry in entries where now.timeIntervalSince(entry.date) > maxAge {
      if (try? fm.removeItem(at: entry.url)) != nil { removed += 1 }
    }
    entries = entries.filter { now.timeIntervalSince($0.date) <= maxAge }
    var total = entries.reduce(Int64(0)) { $0 + $1.size }
    for entry in entries.sorted(by: { $0.date < $1.date }) where total > maxBytes {
      if (try? fm.removeItem(at: entry.url)) != nil { total -= entry.size; removed += 1 }
    }
    return removed
  }
}

private final class GIFDownloadNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}
