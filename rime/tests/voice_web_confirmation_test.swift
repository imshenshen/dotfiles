import Foundation

// Models the observed Codex IMK contract: selected/marked range is available,
// while the substring getter returns stale text for an uncommitted composition.
// This is a host-contract regression, not automation of the actual Codex UI.
@MainActor final class WebHost: VoiceTextHost {
  var document = ""
  var actualSelection = NSRange(location: 0, length: 0)
  var actualMarked = NSRange(location: NSNotFound, length: 0)
  var reportsMarkedSelection: Bool { true }
  var ownsNativeComposition: Bool { native }
  var native = true
  var staleMarkedText = true
  var staleFinalText = false
  private var lastCommitted: NSRange?
  var delayedRanges = false
  var relativeSelection = false
  var caretSelection = false
  var rejectWrites = false
  var writes = 0
  private var previousSelection = NSRange(location: 0, length: 0)
  private var previousMarked = NSRange(location: NSNotFound, length: 0)
  private var ready = Date.distantPast
  var selection: NSRange {
    if Date() < ready { return previousSelection }
    if relativeSelection, actualMarked.location != NSNotFound {
      return NSRange(location: actualSelection.location-actualMarked.location, length: actualSelection.length)
    }
    return actualSelection
  }
  var marked: NSRange { Date() < ready ? previousMarked : actualMarked }
  func text(in range: NSRange) -> String? {
    guard range.location != NSNotFound, NSMaxRange(range) <= document.utf16.count else { return nil }
    if range.length > 0 && (staleMarkedText && actualMarked == range || staleFinalText && lastCommitted == range) {
      return String(repeating: "?", count: range.length) // Same length, wrong body (as in the trace).
    }
    return (document as NSString).substring(with: range)
  }
  private func write(_ text: String, replacing range: NSRange, final: Bool) {
    writes += 1
    guard !rejectWrites else { return }
    previousSelection = actualSelection; previousMarked = actualMarked
    document = (document as NSString).replacingCharacters(in: range, with: text)
    lastCommitted = final ? NSRange(location: range.location, length: text.utf16.count) : nil
    actualMarked = final ? NSRange(location: NSNotFound, length: 0) : NSRange(location: range.location, length: text.utf16.count)
    actualSelection = final || caretSelection ? NSRange(location: range.location+text.utf16.count, length: 0) : actualMarked
    ready = delayedRanges ? Date().addingTimeInterval(0.1) : .distantPast
  }
  func mark(_ text: String, replacing range: NSRange) { write(text, replacing: range, final: false) }
  func insert(_ text: String, replacing range: NSRange) { write(text, replacing: range, final: true) }
  func manuallyAppend(_ text: String) {
    actualMarked = NSRange(location: NSNotFound, length: 0)
    document += text
    actualSelection = NSRange(location: document.utf16.count, length: 0); ready = .distantPast
  }
}

@main struct WebConfirmationTest {
  @MainActor static func main() async {
    let web = WebHost(), editing = VoiceEditing()
    precondition(editing.begin(web))
    for text in ["你", "你好", "你好，这是", "你好，这是持续上屏🧪"] {
      let accepted = await editing.receiveConfirmed(text, final: false)
      precondition(accepted && editing.validate() && !editing.suppressed)
      precondition(web.document == text)
    }
    web.staleFinalText = true
    let finalized = await editing.receiveConfirmed("你好，这是持续上屏🧪。", final: true)
    precondition(finalized && web.document == "你好，这是持续上屏🧪。")
    print("PASS: Codex-like stale substring + selected marked range supports continuous native composition and final commit")

    // Protect user edits, reject old audio revisions, resume only at the next segment.
    web.staleFinalText = false
    editing.protect(); web.manuallyAppend("[KEEP]")
    precondition(!editing.receive("旧段改写", final: false))
    precondition(editing.resumeAfterManualEdit())
    let resumed = await editing.receiveConfirmed("后续语音", final: false)
    let resumedFinal = await editing.receiveConfirmed("后续语音。", final: true)
    precondition(resumed && resumedFinal)
    precondition(web.document == "你好，这是持续上屏🧪。[KEEP]后续语音。")
    print("PASS: manual [KEEP] survives stale results and later speech resumes in chronological order")

    let delayed = WebHost(), waiting = VoiceEditing(); delayed.delayedRanges = true
    precondition(waiting.begin(delayed))
    let delayedAccepted = await waiting.receiveConfirmed("延迟回读", final: false)
    precondition(delayedAccepted && delayed.writes == 1)
    print("PASS: delayed range acknowledgement retries reads without repeating the write")

    let interrupted = WebHost(), safe = VoiceEditing(); interrupted.delayedRanges = true
    precondition(safe.begin(interrupted))
    let task = Task { @MainActor in await safe.receiveConfirmed("原语音", final: false) }
    try? await Task.sleep(nanoseconds: 20_000_000)
    safe.protect(); interrupted.manuallyAppend("[MANUAL]")
    let accepted = await task.value
    precondition(!accepted && interrupted.document == "原语音[MANUAL]" && interrupted.writes == 1)
    print("PASS: manual edit during acknowledgement revokes the pending write and is never overwritten")

    // Replay the actual nonzero-offset trace; the earlier tests at offset zero
    // could not distinguish absolute and composition-relative selections.
    for caret in [false, true] {
      let relative = WebHost(), relativeEditing = VoiceEditing()
      let prefix = "已有文档🙂" + String(repeating: "字", count: 43)
      relative.document = prefix; relative.actualSelection = NSRange(location: prefix.utf16.count, length: 0)
      relative.relativeSelection = true; relative.caretSelection = caret
      precondition(relativeEditing.begin(relative))
      for text in ["你", "你好啊", "一二三四五六七", "一二三四五六七八九十"] {
        let ok = await relativeEditing.receiveConfirmed(text, final: false)
        precondition(ok && relativeEditing.validate() && relative.document == prefix+text)
      }
      relativeEditing.protect(); relative.manuallyAppend("[KEEP]")
      precondition(relativeEditing.resumeAfterManualEdit())
      let part = await relativeEditing.receiveConfirmed("继续输入", final: false)
      let final = await relativeEditing.receiveConfirmed("继续输入。", final: true)
      precondition(part && final && relative.document == prefix+"一二三四五六七八九十[KEEP]继续输入。")
    }
    print("PASS: nonzero document offset with relative full-selection/caret survives >7 characters, manual edits and later finalization")

    let failed = WebHost(), rejected = VoiceEditing(); failed.rejectWrites = true
    precondition(rejected.begin(failed))
    let ignored = await rejected.receiveConfirmed("不能写", final: false)
    precondition(!ignored && failed.document.isEmpty && failed.writes == 1)
    let strict = WebHost(), strictEditing = VoiceEditing(); strict.native = false
    precondition(strictEditing.begin(strict))
    let unverified = await strictEditing.receiveConfirmed("不可信宿主", final: false)
    precondition(!unverified)
    print("PASS: ignored writes and non-native mismatched text remain untrusted")
  }
}
