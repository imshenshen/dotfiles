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
  private var deliveredPrefixes: [Int64: String] = [:]
  private(set) var attemptedInline = false
  mutating func inlineWriteAttempted() { attemptedInline = true }
  var allowsAutomaticFinalInsertion: Bool { !attemptedInline }
  mutating func deliveredPrefix(start: Double, text: String) { deliveredPrefixes[Self.key(start)] = text }
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
  // After a focus transition, only the tail beyond the sealed prefix may be
  // written inline again. A revision that no longer starts with the sealed
  // text must stay in preview rather than overwrite the visible prefix.
  func inlineRemainder(start: Double, text: String) -> String? {
    guard let prefix = deliveredPrefixes[Self.key(start)] else { return text }
    guard text.hasPrefix(prefix) else { return nil }
    return String(text.dropFirst(prefix.count))
  }
  var all: String { finalized.map(\.text).joined() + (partial?.text ?? "") }
  private func remainder(_ segment: VoiceSegment) -> String {
    if wasDelivered(start: segment.start) { return "" }
    if let prefix = deliveredPrefixes[Self.key(segment.start)], segment.text.hasPrefix(prefix) {
      return String(segment.text.dropFirst(prefix.count))
    }
    // A revision that disagrees with the sealed prefix requires review; it
    // stays in preview/history and is never automatically replayed.
    return segment.text
  }
  var remaining: String { finalized.map(remainder).joined() + (partial.map(remainder) ?? "") }
}

struct VoiceContextContinuity {
  enum State { case ready, waiting, preview }
  private var missingSince: TimeInterval?
  mutating func observe(sameApplication: Bool, attached: Bool, now: TimeInterval) -> State {
    guard sameApplication else { return .preview }
    if attached { missingSince = nil; return .ready }
    if missingSince == nil { missingSince = now }
    return now - missingSince! >= 0.3 ? .preview : .waiting
  }
}

// A focus change or a temporary native-controller loss may resume inline once
// the original app has an editable focus again. Unconfirmed writes and manual
// edits stay in preview: replaying them could duplicate or overwrite text.
enum VoicePreviewReason: String {
  case focusChange = "focus-change"
  case inputContextLost = "input-context-lost"
  case composing
  case manualEdit = "manual-edit"
  case writeUnconfirmed = "write-unconfirmed"
  case revisionMismatch = "revision-mismatch"
  var canResume: Bool {
    switch self {
    case .focusChange, .inputContextLost, .composing: return true
    case .manualEdit, .writeUnconfirmed, .revisionMismatch: return false
    }
  }
}
