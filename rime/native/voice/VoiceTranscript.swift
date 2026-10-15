import Foundation

struct VoiceSegment: Equatable {
  let start: Double
  let end: Double
  let text: String
}

struct VoiceTranscript {
  private(set) var finalized: [VoiceSegment] = []
  private(set) var partial: VoiceSegment?
  private var deliveredStarts: Set<Int64> = []
  static func key(_ time: Double) -> Int64 { Int64((time * 1000).rounded()) }
  mutating func update(text: String, start: Double, end: Double, final: Bool) {
    let segment = VoiceSegment(start: start, end: end, text: text)
    if final {
      finalized.removeAll { Self.key($0.start) == Self.key(start) }
      finalized.append(segment); finalized.sort { $0.start < $1.start }
      if let pending = partial, pending.start < end - 0.001 && pending.end > start + 0.001 { partial = nil }
    } else {
      guard !finalized.contains(where: { start < $0.end - 0.001 && end <= $0.end + 0.001 }) else { return }
      partial = segment
    }
  }
  mutating func delivered(start: Double) { deliveredStarts.insert(Self.key(start)) }
  func wasDelivered(start: Double) -> Bool { deliveredStarts.contains(Self.key(start)) }
  var all: String { finalized.map(\.text).joined() + (partial?.text ?? "") }
  var remaining: String {
    finalized.filter { !wasDelivered(start: $0.start) }.map(\.text).joined()
      + (partial.flatMap { wasDelivered(start: $0.start) ? nil : $0.text } ?? "")
  }
}
