import Foundation
@main struct VoiceTranscriptTest {
  static func main() {
    var transcript = VoiceTranscript()
    transcript.update(text: "你", start: 0, end: 0.4, final: false)
    transcript.update(text: "你好", start: 0, end: 1, final: false)
    precondition(transcript.remaining == "你好")
    transcript.update(text: "你好。", start: 0, end: 1.1, final: true)
    transcript.delivered(start: 0)
    precondition(transcript.remaining.isEmpty)
    transcript.update(text: "下一段", start: 1.5, end: 2, final: false)
    precondition(transcript.remaining == "下一段")
    transcript.update(text: "下一段。", start: 1.5, end: 2.2, final: true)
    precondition(transcript.remaining == "下一段。")
    transcript.update(text: "旧结果", start: 1.5, end: 2, final: false)
    precondition(transcript.remaining == "下一段。")
    transcript.delivered(start: 1.50001)
    precondition(transcript.remaining.isEmpty)
    precondition(transcript.all == "你好。下一段。")
    var adjacent = VoiceTranscript()
    adjacent.update(text: "乙", start: 1, end: 2, final: false)
    adjacent.update(text: "甲。", start: 0, end: 1, final: true)
    precondition(adjacent.all == "甲。乙")
    print("Transcript partial replacement, delivered segments and cross-app remainder: passed")
  }
}
