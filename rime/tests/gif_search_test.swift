import Foundation

final class GIFStubURLProtocol: URLProtocol {
  static var status = 200
  static var body = Data()
  static var contentType = "application/json"
  static var requests: [URLRequest] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests.append(request)
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                   httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Type": Self.contentType])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main struct GIFSearchTest {
  static func session() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GIFStubURLProtocol.self]
    return URLSession(configuration: configuration)
  }

  static func service(_ provider: GIFProvider, endpoint: String) throws -> GIFSearchService {
    try GIFSearchService(provider: provider,
                         endpoint: endpoint.isEmpty ? (provider.defaultEndpoint?.absoluteString ?? "") : endpoint,
                         key: "secret-key", rating: .moderate, session: session())
  }

  static func main() async throws {
    GIFStubURLProtocol.status = 200
    GIFStubURLProtocol.contentType = "application/json"
    GIFStubURLProtocol.requests = []
    GIFStubURLProtocol.body = Data("""
    {"data":[{"id":"g1","title":"Cat","url":"https://giphy.com/gifs/g1",
      "images":{"fixed_width_small":{"url":"https://media.giphy.com/media/g1/100w.gif"},
      "original":{"url":"https://media.giphy.com/media/g1/giphy.gif","width":"480","height":"270"}}}],
      "pagination":{"total_count":50,"count":1,"offset":0}}
    """.utf8)
    let giphy = try service(.giphy, endpoint: "")
    let first = try await giphy.search("cat")
    precondition(first.items.count == 1)
    let item = first.items[0]
    precondition(item.id == "g1" && item.title == "Cat" && item.provider == .giphy)
    precondition(item.width == 480 && item.height == 270 && item.sourceURL?.host == "giphy.com")
    precondition(item.thumbnailURL.absoluteString.contains("100w.gif"))
    precondition(first.next == "1")
    var request = GIFStubURLProtocol.requests.last!
    var query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
    precondition(request.httpMethod == "GET")
    precondition(value("q") == "cat" && value("api_key") == "secret-key")
    precondition(value("limit") == "24" && value("offset") == "0" && value("rating") == "pg-13")
    precondition(request.value(forHTTPHeaderField: "Accept") == "application/json")
    precondition(request.url?.scheme == "https")

    GIFStubURLProtocol.body = Data("""
    {"results":[{"id":"t1","content_description":"Dog","itemurl":"https://tenor.com/view/dog",
      "media_formats":{"tinygif":{"url":"https://media.tenor.com/t1/tiny.gif","dims":[220,220]},
      "gif":{"url":"https://media.tenor.com/t1/full.gif","dims":[498,498]}}}],"next":"CAES"}
    """.utf8)
    let tenor = try service(.tenor, endpoint: "")
    let page = try await tenor.search("dog", cursor: "prev")
    precondition(page.items.count == 1 && page.next == "CAES")
    precondition(page.items[0].thumbnailURL.absoluteString.contains("tiny.gif"))
    precondition(page.items[0].gifURL.absoluteString.contains("full.gif"))
    precondition(page.items[0].width == 498 && page.items[0].height == 498)
    request = GIFStubURLProtocol.requests.last!
    query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(value("key") == "secret-key" && value("client_key") == "rime_squirrel")
    precondition(value("contentfilter") == "medium" && value("pos") == "prev")

    GIFStubURLProtocol.body = Data("""
    {"items":[{"id":"c1","title":"Wave","thumbnail_url":"https://cdn.example/thumb.gif",
      "gif_url":"https://cdn.example/full.gif","width":10,"height":20,
      "source_url":"https://example.com/page"}],"next_offset":24,"has_more":true}
    """.utf8)
    let custom = try service(.custom, endpoint: "https://proxy.example/search")
    let customPage = try await custom.search("wave", cursor: "0")
    precondition(customPage.items.count == 1 && customPage.next == "24")
    request = GIFStubURLProtocol.requests.last!
    precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
    query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(value("q") == "wave" && value("limit") == "24" && value("offset") == "0")

    // Unsafe media URLs never reach the palette.
    GIFStubURLProtocol.body = Data("""
    {"items":[{"id":"bad","title":"Bad","thumbnail_url":"https://127.0.0.1/t.gif",
      "gif_url":"https://cdn.example/full.gif"}]}
    """.utf8)
    let unsafe = try await custom.search("bad")
    precondition(unsafe.items.isEmpty)

    GIFStubURLProtocol.status = 500
    do {
      _ = try await custom.search("server-error")
      preconditionFailure("HTTP 500 must throw")
    } catch let error as GIFSearchError {
      guard case .http(500) = error else { preconditionFailure("wrong error: \(error)") }
      precondition(!error.localizedDescription.contains("secret-key"))
      precondition(!error.localizedDescription.contains("server-error"))
    }

    GIFStubURLProtocol.status = 200
    GIFStubURLProtocol.body = Data("not json".utf8)
    do {
      _ = try await custom.search("bad-json")
      preconditionFailure("invalid JSON must throw")
    } catch let error as GIFSearchError {
      guard case .invalidResponse = error else { preconditionFailure("wrong error: \(error)") }
    }

    do {
      _ = try await custom.search("")
      preconditionFailure("empty query must throw")
    } catch let error as GIFSearchError {
      guard case .emptyQuery = error else { preconditionFailure("wrong error: \(error)") }
    }

    do {
      _ = try GIFSearchService(provider: .custom, endpoint: "http://proxy.example/search",
                               key: "", rating: .safe, session: session())
      preconditionFailure("plain HTTP endpoint must be rejected")
    } catch let error as GIFSearchError {
      guard case .configuration = error else { preconditionFailure("wrong error: \(error)") }
    }
    do {
      _ = try GIFSearchService(provider: .giphy, endpoint: "", key: "",
                               rating: .safe, session: session())
      preconditionFailure("official provider without a key must be rejected")
    } catch let error as GIFSearchError {
      guard case .configuration = error else { preconditionFailure("wrong error: \(error)") }
    }

    precondition(GIFSearchService.isSafeHTTPS(URL(string: "https://media.giphy.com/a.gif")!))
    precondition(GIFSearchService.isSafeMedia(URL(string: "https://media.giphy.com/a.gif")!, provider: .giphy))
    precondition(GIFSearchService.isSafeMedia(URL(string: "https://media.tenor.com/a.gif")!, provider: .tenor))
    precondition(!GIFSearchService.isSafeMedia(URL(string: "https://cdn.example/a.gif")!, provider: .giphy))
    precondition(!GIFSearchService.isSafeMedia(URL(string: "https://giphy.com.evil.example/a.gif")!, provider: .giphy))
    precondition(GIFSearchService.isSafeMedia(URL(string: "https://cdn.example/a.gif")!, provider: .custom))
    for unsafe in ["http://media.giphy.com/a.gif", "https://localhost/a.gif",
                   "https://127.0.0.1/a.gif", "https://10.1.2.3/a.gif",
                   "https://192.168.1.2/a.gif", "https://172.20.1.2/a.gif",
                   "https://[::1]/a.gif"] {
      precondition(!GIFSearchService.isSafeHTTPS(URL(string: unsafe)!), "unsafe URL accepted: \(unsafe)")
    }
    print("PASS: Giphy/Tenor/custom requests, pagination and parsing, safe media hosts, configuration and error descriptions")
  }
}
