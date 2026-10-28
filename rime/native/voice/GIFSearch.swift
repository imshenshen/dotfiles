import Foundation

enum GIFProvider: String, CaseIterable, Sendable {
  case giphy
  case tenor
  case custom

  var title: String {
    switch self {
    case .giphy: return "Giphy"
    case .tenor: return "Tenor"
    case .custom: return "自定义 / 代理"
    }
  }

  var defaultEndpoint: URL? {
    switch self {
    case .giphy: return URL(string: "https://api.giphy.com/v1/gifs/search")
    case .tenor: return URL(string: "https://tenor.googleapis.com/v2/search")
    case .custom: return nil
    }
  }

  var keyRequired: Bool { self != .custom }
}

enum GIFRating: String, CaseIterable, Sendable {
  case safe
  case moderate
  case off

  var title: String {
    switch self {
    case .safe: return "安全"
    case .moderate: return "适中"
    case .off: return "不限"
    }
  }

  var giphy: String? {
    switch self {
    case .safe: return "g"
    case .moderate: return "pg-13"
    case .off: return nil
    }
  }

  var tenor: String {
    switch self {
    case .safe: return "high"
    case .moderate: return "medium"
    case .off: return "low"
    }
  }
}

struct GIFItem: Identifiable, Equatable, Sendable {
  let id: String
  let title: String
  let thumbnailURL: URL
  let gifURL: URL
  let sourceURL: URL?
  let width: Int
  let height: Int
  let provider: GIFProvider
}

struct GIFSearchPage: Equatable, Sendable {
  let items: [GIFItem]
  let next: String?
}

enum GIFSearchError: LocalizedError {
  case configuration
  case emptyQuery
  case http(Int)
  case invalidResponse
  case tooLarge
  case transport
  case unsafeURL

  var errorDescription: String? {
    switch self {
    case .configuration: return "请先在“GIF 搜索设置…”中填写服务、Endpoint 和 API Key。"
    case .emptyQuery: return "请输入搜索关键词。"
    case .http(let code): return "GIF 服务请求失败（HTTP \(code)）。"
    case .invalidResponse: return "GIF 服务返回了无法识别的结果。"
    case .tooLarge: return "GIF 服务返回的数据过大。"
    case .transport: return "GIF 服务连接失败或超时。"
    case .unsafeURL: return "GIF 服务返回了不安全的链接。"
    }
  }
}

struct GIFSettings {
  static let defaults = UserDefaults(suiteName: "im.rime.inputmethod.Squirrel.GIF")!

  static var provider: GIFProvider {
    get { GIFProvider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .giphy }
    set { defaults.set(newValue.rawValue, forKey: "provider") }
  }
  static var endpoint: String {
    get { defaults.string(forKey: "endpoint") ?? "" }
    set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "endpoint") }
  }
  static var rating: GIFRating {
    get { GIFRating(rawValue: defaults.string(forKey: "rating") ?? "") ?? .moderate }
    set { defaults.set(newValue.rawValue, forKey: "rating") }
  }
  static var resolvedEndpoint: URL? {
    let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    if !value.isEmpty { return URL(string: value) }
    return provider.defaultEndpoint
  }
  static func save(provider: GIFProvider, endpoint: String, rating: GIFRating) {
    self.provider = provider; self.endpoint = endpoint; self.rating = rating
  }
}

private final class GIFNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}

struct GIFSearchService {
  let provider: GIFProvider
  let endpoint: URL
  let key: String
  let rating: GIFRating
  let session: URLSession

  init(provider: GIFProvider = GIFSettings.provider, endpoint: String = GIFSettings.endpoint,
       key: String, rating: GIFRating = GIFSettings.rating, session: URLSession? = nil) throws {
    guard let url = endpoint.isEmpty ? provider.defaultEndpoint : URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines)),
          Self.isSafeHTTPS(url) else { throw GIFSearchError.configuration }
    if provider.keyRequired && key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw GIFSearchError.configuration
    }
    if provider == .custom && endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw GIFSearchError.configuration
    }
    self.provider = provider; self.endpoint = url
    self.key = key.trimmingCharacters(in: .whitespacesAndNewlines)
    self.rating = rating
    if let session { self.session = session }
    else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 8
      configuration.timeoutIntervalForResource = 20
      configuration.urlCache = nil; configuration.httpCookieStorage = nil
      configuration.urlCredentialStorage = nil
      self.session = URLSession(configuration: configuration, delegate: GIFNoRedirect(), delegateQueue: nil)
    }
  }

  func search(_ rawQuery: String, cursor: String? = nil) async throws -> GIFSearchPage {
    let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { throw GIFSearchError.emptyQuery }
    guard query.count <= 80 else { throw GIFSearchError.emptyQuery }
    let request = try Self.request(provider: provider, endpoint: endpoint, key: key, rating: rating, query: query, cursor: cursor)
    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      if Task.isCancelled { throw CancellationError() }
      throw GIFSearchError.transport
    }
    guard let http = response as? HTTPURLResponse else { throw GIFSearchError.transport }
    guard (200..<300).contains(http.statusCode) else { throw GIFSearchError.http(http.statusCode) }
    guard data.count <= 2_000_000 else { throw GIFSearchError.tooLarge }
    return try Self.parse(provider: provider, data: data, requestedOffset: Int(cursor ?? "0") ?? 0)
  }

  static func request(provider: GIFProvider, endpoint: URL, key: String, rating: GIFRating,
                      query: String, cursor: String?) throws -> URLRequest {
    guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
      throw GIFSearchError.configuration
    }
    var items = components.queryItems ?? []
    func add(_ name: String, _ value: String) { items.removeAll { $0.name == name }; items.append(.init(name: name, value: value)) }
    add("q", query); add("limit", "24")
    switch provider {
    case .giphy:
      add("api_key", key)
      if let value = rating.giphy { add("rating", value) }
      add("offset", cursor ?? "0")
    case .tenor:
      add("key", key); add("client_key", "rime_squirrel")
      add("contentfilter", rating.tenor)
      add("media_filter", "tinygif,gif")
      if let cursor, !cursor.isEmpty { add("pos", cursor) }
    case .custom:
      add("offset", cursor ?? "0")
    }
    components.queryItems = items
    guard let url = components.url, isSafeHTTPS(url) else { throw GIFSearchError.configuration }
    var request = URLRequest(url: url, timeoutInterval: 8)
    request.httpMethod = "GET"
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("RimeGIFSearch/1.0", forHTTPHeaderField: "User-Agent")
    if provider == .custom, !key.isEmpty {
      request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    }
    return request
  }

  static func parse(provider: GIFProvider, data: Data, requestedOffset: Int = 0) throws -> GIFSearchPage {
    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw GIFSearchError.invalidResponse
    }
    switch provider {
    case .giphy: return try parseGiphy(root, requestedOffset: requestedOffset)
    case .tenor: return try parseTenor(root)
    case .custom: return try parseCustom(root)
    }
  }

  private static func parseGiphy(_ root: [String: Any], requestedOffset: Int) throws -> GIFSearchPage {
    guard let rows = root["data"] as? [[String: Any]] else { throw GIFSearchError.invalidResponse }
    let items = rows.compactMap { row -> GIFItem? in
      guard let id = row["id"] as? String,
            let images = row["images"] as? [String: Any],
            let thumbnail = imageURL(images, keys: ["fixed_width_small", "fixed_width", "downsized"]),
            let gif = imageURL(images, keys: ["original", "downsized", "fixed_width"]),
            let thumbURL = URL(string: thumbnail), let gifURL = URL(string: gif),
            isSafeMedia(thumbURL, provider: .giphy), isSafeMedia(gifURL, provider: .giphy) else { return nil }
      let original = images["original"] as? [String: Any]
      let source = (row["url"] as? String).flatMap(URL.init(string:))
      return GIFItem(id: id, title: row["title"] as? String ?? "", thumbnailURL: thumbURL, gifURL: gifURL,
                     sourceURL: source, width: number(original?["width"]), height: number(original?["height"]), provider: .giphy)
    }
    let pagination = root["pagination"] as? [String: Any]
    let total = number(pagination?["total_count"]), count = number(pagination?["count"])
    let offset = number(pagination?["offset"], fallback: requestedOffset)
    let next = (count > 0 && offset + count < total) ? String(offset + count) : nil
    return GIFSearchPage(items: items, next: next)
  }

  private static func parseTenor(_ root: [String: Any]) throws -> GIFSearchPage {
    guard let rows = root["results"] as? [[String: Any]] else { throw GIFSearchError.invalidResponse }
    let items = rows.compactMap { row -> GIFItem? in
      guard let id = row["id"] as? String,
            let formats = row["media_formats"] as? [String: Any],
            let thumbnail = formatURL(formats, keys: ["tinygif", "nanogif", "gif"]),
            let gif = formatURL(formats, keys: ["gif", "tinygif", "mediumgif"]),
            let thumbURL = URL(string: thumbnail), let gifURL = URL(string: gif),
            isSafeMedia(thumbURL, provider: .tenor), isSafeMedia(gifURL, provider: .tenor) else { return nil }
      let dims = (formats["gif"] as? [String: Any])?["dims"] as? [Int] ?? []
      let source = (row["itemurl"] as? String ?? row["url"] as? String).flatMap(URL.init(string:))
      return GIFItem(id: id, title: row["content_description"] as? String ?? row["title"] as? String ?? "",
                     thumbnailURL: thumbURL, gifURL: gifURL, sourceURL: source,
                     width: dims.count > 0 ? dims[0] : 0, height: dims.count > 1 ? dims[1] : 0, provider: .tenor)
    }
    let next = (root["next"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    return GIFSearchPage(items: items, next: next)
  }

  private static func parseCustom(_ root: [String: Any]) throws -> GIFSearchPage {
    guard let rows = root["items"] as? [[String: Any]] else { throw GIFSearchError.invalidResponse }
    let items = rows.compactMap { row -> GIFItem? in
      guard let id = row["id"] as? String,
            let thumb = row["thumbnail_url"] as? String, let gif = row["gif_url"] as? String,
            let thumbURL = URL(string: thumb), let gifURL = URL(string: gif),
            isSafeMedia(thumbURL, provider: .custom), isSafeMedia(gifURL, provider: .custom) else { return nil }
      let source = (row["source_url"] as? String ?? row["page_url"] as? String).flatMap(URL.init(string:))
      return GIFItem(id: id, title: row["title"] as? String ?? "", thumbnailURL: thumbURL, gifURL: gifURL,
                     sourceURL: source, width: number(row["width"]), height: number(row["height"]), provider: .custom)
    }
    let hasMore = root["has_more"] as? Bool ?? false
    let next = hasMore ? root["next_offset"].map { String(number($0)) } : nil
    return GIFSearchPage(items: items, next: next)
  }

  private static func imageURL(_ images: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = (images[key] as? [String: Any])?["url"] as? String, !value.isEmpty { return value }
    }
    return nil
  }
  private static func formatURL(_ formats: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = (formats[key] as? [String: Any])?["url"] as? String, !value.isEmpty { return value }
    }
    return nil
  }
  private static func number(_ value: Any?, fallback: Int = 0) -> Int {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) ?? fallback }
    return fallback
  }

  static func isSafeMedia(_ url: URL, provider: GIFProvider) -> Bool {
    guard isSafeHTTPS(url), let host = url.host?.lowercased() else { return false }
    switch provider {
    case .giphy:
      return host == "giphy.com" || host.hasSuffix(".giphy.com")
    case .tenor:
      return host == "tenor.com" || host.hasSuffix(".tenor.com")
    case .custom:
      return true
    }
  }

  static func isSafeHTTPS(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
          let host = url.host?.lowercased(), !host.isEmpty else { return false }
    if host == "localhost" || host.hasSuffix(".local") { return false }
    if host.contains(":") { // IPv6 literal
      return !(host == "::1" || host.hasPrefix("fc") || host.hasPrefix("fd") || host.hasPrefix("fe80"))
    }
    let parts = host.split(separator: ".").compactMap { Int($0) }
    if parts.count == 4 {
      if parts[0] == 0 || parts[0] == 10 || parts[0] == 127 || (parts[0] == 192 && parts[1] == 168) ||
          (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 169 && parts[1] == 254) {
        return false
      }
    }
    return true
  }
}
