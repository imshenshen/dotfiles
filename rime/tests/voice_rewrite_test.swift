import Foundation

final class MockRewriteProtocol: URLProtocol {
  static var requestSeen: URLRequest?
  static var status = 200
  static var payload = Data()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requestSeen = request
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.payload); client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

@main struct RewriteTest {
  static func main() async throws {
    let text = "已上屏的第一句。黑条中的第二句。保留 Mac Pro、不要改 123。"
    let request = try VoiceRewriteService.request(text: text, level: .tidy, model: "test-model", key: "test-only-key")
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let messages = body["messages"] as! [[String: String]]
    precondition(messages[1]["content"] == text)
    precondition(request.url == VoiceRewriteService.endpoint && request.httpMethod == "POST")
    precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only-key")
    precondition((body["thinking"] as! [String: String])["type"] == "disabled")
    precondition(body["stream"] as? Bool == false)
    precondition(Set(body.keys) == Set(["model","messages","stream","thinking","max_completion_tokens"]))
    let deep = try VoiceRewriteService.request(text: text, level: .restructure, model: "test-model", key: "test-only-key")
    let deepBody = try JSONSerialization.jsonObject(with: deep.httpBody!) as! [String: Any]
    precondition((deepBody["messages"] as! [[String: String]])[0] != messages[0])
    for (source, model, key) in [("", "m", "k"), ("文字", "", "k"), ("文字", "m", ""), (String(repeating: "字", count: 20001), "m", "k")] {
      do { _ = try VoiceRewriteService.request(text: source, level: .tidy, model: model, key: key); preconditionFailure() } catch is VoiceRewriteError { }
    }
    func payload(_ reason: String, _ text: String) throws -> Data {
      try JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": text, "reasoning_content": "never show this", "tool_calls": NSNull()], "finish_reason": reason]]])
    }
    MockRewriteProtocol.payload = try payload("stop", "整理后的正文")
    let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockRewriteProtocol.self]
    let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
    let result = try await VoiceRewriteService(session: session).rewrite(text: text, level: .tidy, model: "test-model", key: "test-only-key")
    precondition(result == "整理后的正文" && MockRewriteProtocol.requestSeen?.url == VoiceRewriteService.endpoint)
    for reason in ["length", "content_filter", "tool_calls"] {
      do { _ = try VoiceRewriteService.response(payload(reason,"不完整正文"), status: 200); preconditionFailure() } catch VoiceRewriteError.incomplete { }
    }
    do { _ = try VoiceRewriteService.response(Data("{bad json".utf8), status: 200); preconditionFailure() } catch VoiceRewriteError.invalidResponse { }
    do { _ = try VoiceRewriteService.response(Data(), status: 401); preconditionFailure() } catch VoiceRewriteError.http(401) { }
    print("PASS: exact full-session text, separate rewrite levels, credential/input validation, mocked HTTP, no reasoning output and incomplete/error rejection")
  }
}
