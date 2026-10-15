import Foundation
import zlib

func response(_ object: [String: Any], flags: UInt8 = 1, compressed: Bool = false) throws -> Data {
  var payload = try JSONSerialization.data(withJSONObject: object)
  if compressed { payload = try gzip(payload) }
  var data = Data([0x11, 0x90 | flags, compressed ? 0x11 : 0x10, 0])
  if flags & 1 != 0 { var sequence = UInt32(1).bigEndian; withUnsafeBytes(of: &sequence) { data.append(contentsOf: $0) } }
  var size = UInt32(payload.count).bigEndian; withUnsafeBytes(of: &size) { data.append(contentsOf: $0) }
  data.append(payload); return data
}
func gzip(_ data: Data) throws -> Data {
  var stream = z_stream()
  precondition(deflateInit2_(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK)
  defer { deflateEnd(&stream) }
  return data.withUnsafeBytes { input in
    stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress); stream.avail_in = uInt(input.count)
    var output = [UInt8](repeating: 0, count: Int(deflateBound(&stream, uLong(data.count))))
    let count = output.withUnsafeMutableBytes { buffer -> Int in
      stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress; stream.avail_out = uInt(buffer.count)
      precondition(deflate(&stream, Z_FINISH) == Z_STREAM_END); return buffer.count - Int(stream.avail_out)
    }
    return Data(output.prefix(count))
  }
}
@main struct ProtocolTest {
  static func main() throws {
    let initial = try DoubaoProtocol.initial(), bytes = [UInt8](initial)
    precondition(Array(bytes.prefix(4)) == [0x11,0x10,0x10,0])
    let payload = try JSONSerialization.jsonObject(with: Data(bytes.dropFirst(8))) as! [String: Any]
    let request = payload["request"] as! [String: Any]
    precondition(request["enable_nonstream"] as? Bool == true && request["show_utterances"] as? Bool == true)
    precondition(request["end_window_size"] as? Int == 1600)
    let slow = try DoubaoProtocol.initial(pauseMilliseconds: 2500)
    let slowPayload = try JSONSerialization.jsonObject(with: Data(slow.dropFirst(8))) as! [String: Any]
    precondition((slowPayload["request"] as! [String: Any])["end_window_size"] as? Int == 2500)
    precondition(request["corpus"] == nil)
    let hotFrame = try DoubaoProtocol.initial(hotwords: ["AI助手", "Mac \"Pro\"", "AI助手", ""])
    let hotPayload = try JSONSerialization.jsonObject(with: Data(hotFrame.dropFirst(8))) as! [String: Any]
    let corpus = (hotPayload["request"] as! [String: Any])["corpus"] as! [String: Any]
    precondition(Set(corpus.keys) == ["context"])
    let context = try JSONSerialization.jsonObject(with: Data((corpus["context"] as! String).utf8)) as! [String: Any]
    precondition(Set(context.keys) == ["hotwords"])
    precondition((context["hotwords"] as! [[String: String]]).map { $0["word"]! } == ["AI助手", "Mac \"Pro\""])
    let audio = payload["audio"] as! [String: Any]
    precondition(audio["rate"] as? Int == 16000 && audio["bits"] as? Int == 16 && audio["channel"] as? Int == 1)
    precondition(audio["language"] == nil)
    precondition(Array(DoubaoProtocol.audio(Data(), last: true)) == [0x11,0x22,0,0,0,0,0,0])
    let partial: [String: Any] = ["result": ["utterances": [["text":"中", "start_time":0, "end_time":600, "definite":false]]]]
    let final: [String: Any] = ["result": ["utterances": [["text":"中国。", "start_time":0, "end_time":650, "definite":true]]]]
    let unsequenced = try DoubaoProtocol.unpack(response(partial, flags: 0))
    let missingZeroStart: [String: Any] = ["result": ["utterances": [["text":"你", "end_time":600, "definite":false]]]]
    let firstLive = try DoubaoProtocol.unpack(response(missingZeroStart))
    precondition(firstLive.recognition == [DoubaoRecognition(text:"你",start:0,end:0.6,final:false)])
    let sequenced = try DoubaoProtocol.unpack(response(partial))
    var tracker = DoubaoResultTracker()
    precondition(tracker.changes(unsequenced).count == 1)
    precondition(tracker.changes(sequenced).isEmpty)
    func segment(_ text: String, _ start: Double, _ end: Double, _ final: Bool) -> DoubaoRecognition {
      DoubaoRecognition(text: text, start: start, end: end, final: final)
    }
    func batch(_ values: DoubaoRecognition...) -> DoubaoResponse {
      DoubaoResponse(last: false, recognition: values)
    }
    var reordered = DoubaoResultTracker()
    _ = reordered.changes(batch(segment("甲", 0, 1, false)))
    precondition(reordered.changes(batch(segment("乙", 1, 2, false))).first?.text == "甲乙")
    let earlySecond = reordered.changes(batch(segment("乙。", 1, 2, true)))
    precondition(earlySecond == [segment("甲乙。", 0, 2, false)])
    precondition(reordered.changes(batch(segment("甲。", 0, 1, true))) == [segment("甲。乙。", 0, 2, true)])
    var split = DoubaoResultTracker()
    _ = split.changes(batch(segment("甲", 0, 1, false), segment("乙", 1, 2, false)))
    precondition(split.changes(batch(segment("甲。", 0, 1, true))) == [segment("甲。", 0, 1, true), segment("乙", 1, 2, false)])
    precondition(split.changes(batch(segment("乙。", 1, 2, true))) == [segment("乙。", 1, 2, true)])
    let confirmed = try DoubaoProtocol.unpack(response(final, flags: 3, compressed: true))
    precondition(confirmed.last && confirmed.recognition.first?.text == "中国。")
    precondition(tracker.changes(confirmed).count == 1)
    precondition(tracker.changes(confirmed).isEmpty)
    precondition(tracker.changes(sequenced).isEmpty)
    for bad in [Data(), Data([0x11,0x91,0x10,0]), Data([0x11,0x90,0x10,0,0,0,0,5,123])] {
      do { _ = try DoubaoProtocol.unpack(bad); preconditionFailure("Malformed frame accepted") } catch {}
    }
    let errorFrame = Data([0x11,0xf0,0x10,0,0x02,0xae,0xa5,0x41,0,0,0,4]) + Data("oops".utf8)
    do { _ = try DoubaoProtocol.unpack(errorFrame); preconditionFailure() }
    catch { precondition(!error.localizedDescription.contains("oops")) }
    do { _ = try DoubaoProtocol.gunzip(gzip(Data(repeating: 0, count: DoubaoProtocol.maximumPayload + 1))); preconditionFailure() } catch {}
    let config = DoubaoConfiguration(apiKey:"test-key", appID:"", accessToken:"", resource:"volc.seedasr.sauc.duration")
    let headers = try config.request().allHTTPHeaderFields!
    precondition(headers["X-Api-Key"] == "test-key" && headers["X-Api-App-Key"] == nil)
    let legacy = try DoubaoConfiguration(apiKey:"", appID:"test-app", accessToken:"test-token", resource:"volc.bigasr.sauc.duration").request()
    precondition(legacy.value(forHTTPHeaderField:"X-Api-Access-Key") == "test-token")
    do { _ = try DoubaoConfiguration(apiKey:"", appID:"", accessToken:"", resource:"").request(); preconditionFailure() } catch {}
    print("PASS: two-pass configuration, out-of-order final results and tail re-emission, PCM metadata, sequence/no-sequence/gzip/final/error frames, duplicate and stale results, decompression bounds, new/legacy auth")
  }
}
