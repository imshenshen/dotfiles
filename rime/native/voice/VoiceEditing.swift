import Foundation
import OSLog

// Web/Electron clients may reject explicit ranges but accept the native IME
// sentinel for replacing the current selection or marked composition.
enum VoiceHostRange {
  static func replacement(_ requested: NSRange, selection: NSRange, marked: NSRange) -> NSRange {
    if requested == selection || marked.location != NSNotFound && requested == marked {
      return NSRange(location: NSNotFound, length: 0)
    }
    return requested
  }
}

// Only the owned UTF-16 range is read. No document-wide snapshots or clipboard.
@MainActor public protocol VoiceTextHost: AnyObject {
  var selection: NSRange { get }
  var marked: NSRange { get }
  var reportsMarkedSelection: Bool { get }
  // IMK owns its current marked composition even when a Web/Electron client
  // cannot return that uncommitted text through attributedSubstring yet.
  var ownsNativeComposition: Bool { get }
  func text(in range: NSRange) -> String?
  func mark(_ text: String, replacing range: NSRange)
  func insert(_ text: String, replacing range: NSRange)
}

public extension VoiceTextHost {
  var reportsMarkedSelection: Bool { false }
  var ownsNativeComposition: Bool { false }
}

public struct VoiceOrganizeRequest: Sendable {
  public let text: String
  public let session: UUID
  public let revision: UInt64
  public init(text: String, session: UUID, revision: UInt64) {
    self.text = text; self.session = session; self.revision = revision
  }
}
// Reserved interface; no implementation is configured and nothing is uploaded.
public protocol VoiceTextOrganizer: Sendable {
  func organize(_ request: VoiceOrganizeRequest) async throws -> String
}

@MainActor public final class VoiceEditing {
  private struct Owned {
    var range: NSRange
    var text: String
    var original: String
    var caret: NSRange
  }
  private weak var host: VoiceTextHost?
  private var pending: Owned?
  private var undoItems: [Owned] = []
  private var expectedSelection: NSRange?
  private let logger = Logger(subsystem: "im.rime.inputmethod.Squirrel", category: "VoiceEditing")
  public private(set) var confirming = false
  public private(set) var suppressed = false
  public private(set) var revision: UInt64 = 0

  public init() {}
  public func begin(_ host: VoiceTextHost) -> Bool {
    guard host.selection.location != NSNotFound,
          (host.marked.location == NSNotFound || host.marked.length == 0),
          host.text(in: host.selection) != nil else { return false }
    self.host = host; pending = nil; undoItems = []; suppressed = false
    expectedSelection = host.selection; revision &+= 1
    return true
  }
  private func intact(_ owned: Owned, marked: Bool) -> Bool {
    guard let host, selectionMatches(owned, marked: marked) else { return false }
    if marked {
      guard host.marked == owned.range else { return false }
      if host.ownsNativeComposition { return true }
    }
    return host.text(in: owned.range) == owned.text
  }
  private func selectionMatches(_ owned: Owned, marked: Bool) -> Bool {
    guard let host else { return false }
    let selection = host.selection
    if selection == owned.caret { return true }
    guard marked, host.reportsMarkedSelection, host.marked == owned.range else { return false }
    if selection == owned.range { return true }
    // Some Web IMK clients report selection relative to the marked region
    // (e.g. selected=0:7, marked=49:7). Only accept these coordinates for our
    // live native composition, never for final text or arbitrary document ranges.
    return host.ownsNativeComposition &&
      (selection == NSRange(location: 0, length: owned.range.length) ||
       selection == NSRange(location: owned.range.length, length: 0))
  }
  public func validate() -> Bool {
    guard let host else { return false }
    if let pending { return intact(pending, marked: true) }
    return expectedSelection == host.selection && (host.marked.location == NSNotFound || host.marked.length == 0)
  }
  // At most 32 UTF-16 units immediately before our replacement range.
  var leadingContext: String {
    guard let host else { return "" }
    let location = pending?.range.location ?? host.selection.location
    guard location != NSNotFound, location > 0 else { return "" }
    let length = min(32, location)
    return host.text(in: NSRange(location: location-length, length: length)) ?? ""
  }
  var leadingContextAtStart: Bool {
    guard let host else { return false }
    let location = pending?.range.location ?? host.selection.location
    return location != NSNotFound && location <= 32
  }
  private struct Write {
    let owned: Owned
    let final: Bool
    let nativeMarked: Bool
  }
  private func write(_ text: String, final: Bool) -> Write? {
    guard let host else { return nil }
    if suppressed {
      if final { suppressed = false; expectedSelection = host.selection }
      return nil
    }
    guard validate() else { protect(); return nil }
    let nativeMarked = host.ownsNativeComposition && pending.map { intact($0, marked: true) } == true
    let replacement = pending?.range ?? host.selection
    let original = pending?.original ?? host.text(in: replacement) ?? ""
    if final { host.insert(text, replacing: replacement) }
    else { host.mark(text, replacing: replacement) }
    let range = NSRange(location: replacement.location, length: text.utf16.count)
    let owned = Owned(range: range, text: text, original: original,
                      caret: NSRange(location: NSMaxRange(range), length: 0))
    return Write(owned: owned, final: final, nativeMarked: nativeMarked)
  }
  private func acknowledged(_ write: Write, nativeFinal: Bool = false) -> Bool {
    guard let host else { return false }
    if !write.final { return intact(write.owned, marked: true) }
    guard selectionMatches(write.owned, marked: false),
          host.marked.location == NSNotFound || host.marked.length == 0 else { return false }
    return host.text(in: write.owned.range) == write.owned.text || nativeFinal && write.nativeMarked
  }
  private func accept(_ write: Write) {
    pending = write.final ? nil : write.owned
    if write.final && !write.owned.text.isEmpty { undoItems.append(write.owned) }
    expectedSelection = write.owned.caret; revision &+= 1
  }
  private func reject(_ write: Write) {
    let selection = host?.selection ?? NSRange(location: NSNotFound, length: 0)
    let marked = host?.marked ?? NSRange(location: NSNotFound, length: 0)
    logger.notice("Write unconfirmed after retry: final=\(write.final), selected=\(selection.location):\(selection.length), marked=\(marked.location):\(marked.length), expected=\(write.owned.range.location):\(write.owned.range.length)")
    pending = nil; undoItems = []; suppressed = true; revision &+= 1
  }
  public func receive(_ text: String, final: Bool) -> Bool {
    guard let write = write(text, final: final) else { return false }
    guard acknowledged(write) else { reject(write); return false }
    accept(write); return true
  }
  // Serialized by the session. Polling yields the main actor so host updates,
  // real keystrokes, focus changes and cancellation can all be processed.
  // A revision change revokes the write immediately: never retry a mutation.
  public func receiveConfirmed(_ text: String, final: Bool) async -> Bool {
    guard !confirming, !Task.isCancelled else { return false }
    confirming = true
    defer { confirming = false }
    let token = revision
    guard let write = write(text, final: final) else { return false }
    if !final { pending = write.owned }
    for attempt in 0...10 {
      guard !Task.isCancelled, revision == token else { return false }
      // Finalizing an IMK-owned composition may also have a stale text getter.
      // Only trust the native commit after stable range acknowledgement, and
      // only when the preceding marked composition was verified as ours.
      if acknowledged(write, nativeFinal: attempt >= 2) {
        accept(write); return true
      }
      if attempt < 10 { try? await Task.sleep(nanoseconds: 40_000_000) }
    }
    reject(write); return false
  }
  public func protect() {
    // Seal only a verified marked range; changed text is never overwritten.
    if let pending, intact(pending, marked: true) {
      host?.insert(pending.text, replacing: pending.range)
    }
    pending = nil; undoItems = []; suppressed = true
    expectedSelection = host?.selection; revision &+= 1
  }
  // Called only when the coordinator sees audio beyond the protected segment.
  // The previous segment may already be final, so there is no further final
  // event to release suppression. Resume at the user's current empty caret.
  public func resumeAfterManualEdit() -> Bool {
    guard suppressed, let host, pending == nil,
          host.selection.location != NSNotFound, host.selection.length == 0,
          host.marked.location == NSNotFound || host.marked.length == 0 else { return false }
    expectedSelection = host.selection; suppressed = false; revision &+= 1
    return true
  }
  @discardableResult public func finish(discard: Bool = false) -> Bool {
    var sealed = false
    if let pending, intact(pending, marked: true) {
      host?.insert(discard ? pending.original : pending.text, replacing: pending.range)
      if !discard { undoItems.append(pending) }
      sealed = true
    }
    pending = nil; expectedSelection = host?.selection; revision &+= 1
    return sealed
  }
  public func rebindUndo(to candidate: VoiceTextHost) -> Bool {
    guard pending == nil, let item = undoItems.last,
          candidate.selection == item.caret, candidate.text(in: item.range) == item.text,
          candidate.marked.location == NSNotFound || candidate.marked.length == 0 else { return false }
    host = candidate; expectedSelection = candidate.selection
    return true
  }
  public func undo() -> Bool {
    guard let host, pending == nil, let item = undoItems.last,
          intact(item, marked: false), (host.marked.location == NSNotFound || host.marked.length == 0) else { return false }
    host.insert(item.original, replacing: item.range)
    undoItems.removeLast(); expectedSelection = host.selection; revision &+= 1
    return true
  }
  public func cancelUnedited() {
    finish(discard: true)
    while undo() {}
  }
}
