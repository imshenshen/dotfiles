import Foundation
import AppKit
@MainActor final class CloudTextHost: VoiceTextHost {
  let view = NSTextView()
  var selection: NSRange { view.selectedRange() }
  var marked: NSRange { view.markedRange() }
  func text(in range: NSRange) -> String? {
    guard NSMaxRange(range) <= view.string.utf16.count else { return nil }
    return (view.string as NSString).substring(with: range)
  }
  func mark(_ text: String, replacing range: NSRange) {
    view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: range)
  }
  func insert(_ text: String, replacing range: NSRange) { view.insertText(text, replacementRange: range) }
}
@main struct NetworkTest {
  @MainActor static func main() async throws {
    let port = CommandLine.arguments[1]
    let config = DoubaoConfiguration(apiKey:"test-key",appID:"",accessToken:"",resource:"volc.seedasr.sauc.duration", hotwords:["AI助手", "Mac 电脑"])
    let stream = DoubaoStream(); var events: [DoubaoRecognition] = []; var failures: [String] = []
    let host = CloudTextHost(), editing = VoiceEditing(); precondition(editing.begin(host))
    stream.onResult = { events.append($0); precondition(editing.receive($0.text, final: $0.final)) }; stream.onError = { failures.append($0.localizedDescription) }
    try await stream.start(config, endpoint: URL(string:"ws://127.0.0.1:\(port)/normal")!)
    for _ in 0..<3 { stream.submit(Data(repeating:0,count:6400)); try await Task.sleep(nanoseconds:200_000_000) }
    await stream.finish()
    precondition(failures.isEmpty)
    precondition(events.map(\.text) == ["你","你好","你好。","本地模拟服务。"])
    precondition(events.filter(\.final).count == 2)
    precondition(host.view.string == "你好。本地模拟服务。")
    precondition(editing.undo()); precondition(host.view.string == "你好。")
    precondition(editing.undo()); precondition(host.view.string.isEmpty)
    print("PASS: native WebSocket handshake, 200 ms PCM packets, two-pass corrections, duplicate full-result suppression and final drain")
    let protectedStream = DoubaoStream(), protectedHost = CloudTextHost(), protection = VoiceEditing()
    precondition(protection.begin(protectedHost))
    protectedStream.onResult = { result in
      _ = protection.receive(result.text, final: result.final)
      if result.text == "你" {
        protection.protect(); protectedHost.view.insertText("[keep]", replacementRange:NSRange(location:NSNotFound,length:0))
      }
    }
    try await protectedStream.start(config, endpoint: URL(string:"ws://127.0.0.1:\(port)/normal")!)
    for _ in 0..<3 { protectedStream.submit(Data(repeating:0,count:6400)); try await Task.sleep(nanoseconds:200_000_000) }
    await protectedStream.finish()
    precondition(protectedHost.view.string == "你[keep]本地模拟服务。")
    precondition(protection.undo()); precondition(protectedHost.view.string == "你[keep]")
    precondition(!protection.undo())
    print("PASS: actual NSTextView receives two-pass changes; late correction and voice undo preserve manual [keep]")
    // A second utterance can arrive before the offline correction of the first.
    for secondFinishesFirst in [false, true] {
      let orderedHost = CloudTextHost(), orderedEditing = VoiceEditing()
      precondition(orderedEditing.begin(orderedHost))
      var tracker = DoubaoResultTracker()
      func apply(_ text: String, _ start: Double, _ end: Double, _ final: Bool) {
        let response = DoubaoResponse(last: false, recognition: [DoubaoRecognition(text: text, start: start, end: end, final: final)])
        for result in tracker.changes(response) { precondition(orderedEditing.receive(result.text, final: result.final)) }
      }
      apply("甲", 0, 1, false); apply("乙", 1, 2, false)
      precondition(orderedHost.view.string == "甲乙")
      if secondFinishesFirst { apply("乙。", 1, 2, true); apply("甲。", 0, 1, true) }
      else { apply("甲。", 0, 1, true); apply("乙。", 1, 2, true) }
      precondition(orderedHost.view.string == "甲。乙。")
      while orderedEditing.undo() {}
      precondition(orderedHost.view.string.isEmpty)
    }
    print("PASS: actual NSTextView preserves utterance order for both two-pass final arrival orders and can undo the result")
    for path in ["error", "disconnect"] {
      let fault = DoubaoStream(); var failureMessage: String?
      fault.onError = { failureMessage = $0.localizedDescription }
      do { try await fault.start(config, endpoint: URL(string:"ws://127.0.0.1:\(port)/\(path)")!) }
      catch { failureMessage = error.localizedDescription }
      for _ in 0..<20 { if failureMessage != nil { break }; try await Task.sleep(nanoseconds:50_000_000) }
      precondition(failureMessage != nil && !failureMessage!.contains("test-key")); fault.cancel()
    }
    print("PASS: server error and disconnect terminate without leaking credential or server text")
    let slow = DoubaoStream(); var overflow = false
    slow.onError = { if case DoubaoError.overflow = $0 { overflow = true } }
    try await slow.start(config, endpoint: URL(string:"ws://127.0.0.1:\(port)/overflow")!)
    slow.submit(Data(repeating:0,count:6400 * 102))
    precondition(overflow); slow.cancel()
    let timeout = DoubaoStream(); var expired = false
    timeout.onError = { if case DoubaoError.timeout = $0 { expired = true } }
    try await timeout.start(config, endpoint: URL(string:"ws://127.0.0.1:\(port)/timeout")!)
    timeout.submit(Data(repeating:0,count:6400)); await timeout.finish()
    precondition(expired)
    let cancelled = DoubaoStream(); var unexpectedError = false
    cancelled.onError = { _ in unexpectedError = true }
    try await cancelled.start(config, endpoint: URL(string:"ws://127.0.0.1:\(port)/normal")!)
    cancelled.submit(Data(repeating:0,count:6400)); cancelled.cancel()
    try await Task.sleep(nanoseconds:200_000_000)
    precondition(!unexpectedError)
    print("PASS: explicit cancellation does not report a network failure")
    print("PASS: bounded audio backpressure and final-result timeout stop rather than lose arbitrary audio")
  }
}
