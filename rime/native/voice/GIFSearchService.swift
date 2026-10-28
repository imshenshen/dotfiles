import AppKit
import ImageIO
import UniformTypeIdentifiers

enum GIFImageDecoder {
  static func firstFrame(_ data: Data, maxPixel: Int = 512) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixel,
    ]
    return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
      ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
  }

  static func image(_ data: Data, maxPixel: Int = 512) -> NSImage? {
    guard let frame = firstFrame(data, maxPixel: maxPixel) else { return nil }
    return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
  }
}

@MainActor
final class GIFImageLoader {
  static let shared = GIFImageLoader()
  private let cache = NSCache<NSURL, NSImage>()
  private var loading = Set<URL>()
  private let session: URLSession
  private let maxBytes = 5_000_000

  init(session: URLSession? = nil) {
    if let session { self.session = session }
    else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 8
      configuration.timeoutIntervalForResource = 15
      configuration.urlCache = nil; configuration.httpCookieStorage = nil
      configuration.urlCredentialStorage = nil
      self.session = URLSession(configuration: configuration, delegate: GIFMediaNoRedirect(), delegateQueue: nil)
    }
    cache.countLimit = 180
    cache.totalCostLimit = 48 * 1024 * 1024
  }

  func cached(_ url: URL) -> NSImage? { cache.object(forKey: url as NSURL) }

  func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
    guard GIFSearchService.isSafeHTTPS(url) else { completion(nil); return }
    if let image = cache.object(forKey: url as NSURL) { completion(image); return }
    guard !loading.contains(url) else { return }
    loading.insert(url)
    let task = session.dataTask(with: url) { [weak self] data, response, _ in
      var frame: CGImage?
      if let data, data.count <= 5_000_000,
         let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
        frame = GIFImageDecoder.firstFrame(data, maxPixel: 420)
      }
      DispatchQueue.main.async {
        guard let self else { return }
        let image = frame.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
        self.loading.remove(url)
        if let image { self.cache.setObject(image, forKey: url as NSURL, cost: data?.count ?? 0) }
        completion(image)
      }
    }
    task.resume()
  }

  func clear() {
    cache.removeAllObjects()
    loading.removeAll()
  }
}

private final class GIFMediaNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}
