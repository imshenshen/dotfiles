import Foundation
import zlib
import OSLog

enum DoubaoError: LocalizedError {
  case hotwordSize, credentials, malformed, compression, overflow, transport, timeout, server(UInt32), handshake(Int)
  var errorDescription: String? {
    switch self {
    case .hotwordSize: return "热词内容超过请求容量，请减少勾选后重试。"
    case .credentials: return "豆包语音凭证不可用，请在配置页重新保存并完成钥匙串授权。"
    case .malformed, .compression: return "豆包返回了无法解析的识别数据。"
    case .overflow: return "网络处理过慢，已停止录音并保留已识别文字。"
    case .transport: return "豆包连接失败，请检查网络、接口凭证和已开通的模型。"
    case .handshake(let status): return "豆包接口连接被拒绝（HTTP \(status)），请检查语音 API 凭证及对应服务。"
    case .timeout: return "等待豆包最终识别超时，已保留当前结果。"
    case .server(let code): return "豆包识别返回错误 \(code)，请检查服务开通和接口配置。"
    }
  }
}

struct DoubaoConfiguration {
  let apiKey: String
  let appID: String
  let accessToken: String
  let resource: String
  var pauseMilliseconds: Int = 1600
  var hotwords: [String] = []
  static let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async")!
  func request(url: URL = endpoint) throws -> URLRequest {
    guard !apiKey.isEmpty || (!appID.isEmpty && !accessToken.isEmpty) else { throw DoubaoError.credentials }
    var request = URLRequest(url: url, timeoutInterval: 15)
    if !apiKey.isEmpty { request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key") }
    else {
      request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
      request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
    }
    let id = UUID().uuidString
    request.setValue(resource, forHTTPHeaderField: "X-Api-Resource-Id")
    request.setValue(id, forHTTPHeaderField: "X-Api-Request-Id")
    request.setValue(id, forHTTPHeaderField: "X-Api-Connect-Id")
    request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")
    return request
  }
}

struct DoubaoRecognition: Equatable {
  let text: String
  let start: Double
  let end: Double
  let final: Bool
}
struct DoubaoResponse {
  let last: Bool
  let recognition: [DoubaoRecognition]
}

enum DoubaoProtocol {
  static let maximumPayload = 1_048_576
  static func frame(type: UInt8, flags: UInt8 = 0, json: Bool = false, payload: Data) -> Data {
    var data = Data([0x11, (type << 4) | flags, json ? 0x10 : 0x00, 0])
    var size = UInt32(payload.count).bigEndian
    withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }; data.append(payload)
    return data
  }
  static func initial(pauseMilliseconds: Int = 1600, hotwords: [String] = []) throws -> Data {
    var value: [String: Any] = [
      "user": ["uid": UUID().uuidString],
      "audio": ["format": "pcm", "codec": "raw", "rate": 16000, "bits": 16, "channel": 1],
      "request": ["model_name": "bigmodel", "enable_nonstream": true,
                  "show_utterances": true, "result_type": "full", "enable_itn": true,
                  "enable_punc": true, "enable_ddc": false,
                  "end_window_size": min(5000, max(200, pauseMilliseconds))]
    ]
    var seen = Set<String>()
    let words = Array(hotwords.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(5000))
    if !words.isEmpty {
      let context = try JSONSerialization.data(withJSONObject: ["hotwords": words.map { ["word": $0] }])
      var request = value["request"] as! [String: Any]
      request["corpus"] = ["context": String(decoding: context, as: UTF8.self)]
      value["request"] = request
    }
    let payload = try JSONSerialization.data(withJSONObject: value)
    guard payload.count <= maximumPayload else { throw DoubaoError.hotwordSize }
    return frame(type: 1, json: true, payload: payload)
  }

  static func audio(_ data: Data, last: Bool = false) -> Data { frame(type: 2, flags: last ? 2 : 0, payload: data) }
  static func unpack(_ data: Data) throws -> DoubaoResponse {
    let bytes = [UInt8](data)
    guard bytes.count >= 8, bytes[0] >> 4 == 1 else { throw DoubaoError.malformed }
    var offset = Int(bytes[0] & 15) * 4
    guard offset >= 4, offset <= bytes.count - 4 else { throw DoubaoError.malformed }
    let type = bytes[1] >> 4, flags = bytes[1] & 15, compression = bytes[2] & 15
    func number() throws -> UInt32 {
      guard offset + 4 <= bytes.count else { throw DoubaoError.malformed }
      defer { offset += 4 }
      return bytes[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
    var errorCode: UInt32?
    if type == 15 { errorCode = try number() }
    else {
      guard type == 9, bytes[2] >> 4 == 1 else { throw DoubaoError.malformed }
      if flags & 1 != 0 { _ = try number() }
    }
    let count = Int(try number())
    guard count <= maximumPayload, offset + count == bytes.count else {
      Logger(subsystem: "im.rime.inputmethod.Squirrel", category: "Doubao").error("Frame bounds: payload=\(count), offset=\(offset), bytes=\(bytes.count)")
      throw DoubaoError.malformed
    }
    var payload = Data(bytes[offset..<offset + count])
    if compression == 1 { payload = try gunzip(payload) }
    else if compression != 0 { throw DoubaoError.compression }
    // Never display server-supplied error text: it may echo transcript or credentials.
    if let errorCode { throw DoubaoError.server(errorCode) }
    guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else { throw DoubaoError.malformed }
    if let code = object["code"] as? UInt32, code != 0 && code != 20000000 { throw DoubaoError.server(code) }
    let result = object["result"] as? [String: Any]
    var items: [DoubaoRecognition] = []
    for utterance in result?["utterances"] as? [[String: Any]] ?? [] {
      // The live API omits zero-valued start_time on the first utterance.
      // Missing zero is valid; a present nonnumeric value remains invalid.
      let startValue = utterance["start_time"] == nil ? 0.0 : utterance["start_time"] as? Double
      guard let text = utterance["text"] as? String,
            let start = startValue, let end = utterance["end_time"] as? Double,
            start >= 0, end >= start else {
        let hasText = utterance["text"] is String
        let start = utterance["start_time"] as? Double ?? -999, end = utterance["end_time"] as? Double ?? -999
        Logger(subsystem: "im.rime.inputmethod.Squirrel", category: "Doubao").error("Utterance metadata: textPresent=\(hasText), start=\(start), end=\(end)")
        throw DoubaoError.malformed
      }
      items.append(DoubaoRecognition(text: text, start: start / 1000, end: end / 1000,
                                     final: utterance["definite"] as? Bool == true))
    }
    if flags & 4 != 0 {
      Logger(subsystem: "im.rime.inputmethod.Squirrel", category: "Doubao").info("Optimized stream response flag: \(flags)")
    }
    return DoubaoResponse(last: flags & 2 != 0, recognition: items.sorted { $0.start < $1.start })
  }
  static func gunzip(_ input: Data) throws -> Data {
    var stream = z_stream()
    guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw DoubaoError.compression }
    defer { inflateEnd(&stream) }
    return try input.withUnsafeBytes { raw -> Data in
      stream.next_in = UnsafeMutablePointer(mutating: raw.bindMemory(to: Bytef.self).baseAddress)
      stream.avail_in = uInt(raw.count)
      var output = Data(), status: Int32 = Z_OK
      repeat {
        var block = [UInt8](repeating: 0, count: 16384)
        var written = 0
        status = block.withUnsafeMutableBytes { buffer in
          stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(buffer.count)
          let result = inflate(&stream, Z_NO_FLUSH); written = buffer.count - Int(stream.avail_out); return result
        }
        guard status == Z_OK || status == Z_STREAM_END, output.count + written <= maximumPayload else { throw DoubaoError.compression }
        output.append(contentsOf: block.prefix(written))
      } while status != Z_STREAM_END
      guard stream.avail_in == 0 else { throw DoubaoError.compression }
      return output
    }
  }
}

struct DoubaoResultTracker {
  private var pending: [Int64: DoubaoRecognition] = [:]
  private var committed: Set<Int64> = []
  private var emittedPartial: DoubaoRecognition?
  mutating func changes(_ response: DoubaoResponse) -> [DoubaoRecognition] {
    for result in response.recognition {
      let key = VoiceTranscript.key(result.start)
      if committed.contains(key) || pending[key]?.final == true { continue }
      pending[key] = result
    }
    let ordered = pending.values.sorted { $0.start < $1.start }
    let prefix = Array(ordered.prefix { $0.final })
    var changes: [DoubaoRecognition] = []
    if let confirmed = joined(prefix, final: true) {
      changes.append(confirmed)
      for result in prefix {
        let key = VoiceTranscript.key(result.start)
        committed.insert(key); pending.removeValue(forKey: key)
      }
      // Committing replaces the whole marked tail. Re-emit the rest even when
      // its words have not changed, so the following utterance is reinserted.
      emittedPartial = nil
    }
    if let tail = joined(Array(ordered.dropFirst(prefix.count)), final: false), tail != emittedPartial {
      changes.append(tail); emittedPartial = tail
    }
    return changes
  }
  private func joined(_ values: [DoubaoRecognition], final: Bool) -> DoubaoRecognition? {
    guard let first = values.first, let last = values.last else { return nil }
    return DoubaoRecognition(text: values.map(\.text).joined(), start: first.start, end: last.end, final: final)
  }
}
