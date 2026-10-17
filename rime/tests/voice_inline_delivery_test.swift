import Foundation

// A native IMK adapter: requests at the current selection use the native
// sentinel, while subsequent markedRange can use document coordinates.
@MainActor final class InlineHost: VoiceTextHost {
  var document: String
  var actualSelection: NSRange
  var actualMarked = NSRange(location: NSNotFound, length: 0)
  var relativeFinal = false
  var caretAtStart = false
  var unreadable = false
  var exposeMarks = true
  var native = true
  var terminalCells = false
  var usesTerminalCellCoordinates: Bool { terminalCells }
  var committedCellCaret: Int?
  var writes = 0
  private var committedOrigin: Int?
  init(prefix: String = "") { document = prefix; actualSelection = NSRange(location: prefix.utf16.count, length: 0) }
  var ownsNativeComposition: Bool { native }
  var reportsMarkedSelection: Bool { true }
  var selection: NSRange {
    if relativeFinal, actualMarked.location == NSNotFound, let committedOrigin {
      return NSRange(location: actualSelection.location-committedOrigin, length: actualSelection.length)
    }
    if actualMarked.location == NSNotFound, let committedCellCaret { return NSRange(location: committedCellCaret, length: 0) }
    return actualSelection
  }
  var marked: NSRange { exposeMarks ? actualMarked : NSRange(location: NSNotFound, length: 0) }
  func text(in range: NSRange) -> String? {
    if range.length == 0 { return "" }
    guard !unreadable, range.location != NSNotFound, NSMaxRange(range) <= document.utf16.count else { return nil }
    return (document as NSString).substring(with: range)
  }
  private func write(_ text: String, replacing range: NSRange, final: Bool) {
    let target = range == selection ? actualSelection : range
    let actual = range == actualMarked ? actualMarked : target
    document = (document as NSString).replacingCharacters(in: actual, with: text)
    actualMarked = final ? NSRange(location: NSNotFound, length: 0) : NSRange(location: actual.location, length: text.utf16.count)
    actualSelection = NSRange(location: !final && caretAtStart ? actual.location : actual.location+text.utf16.count, length: 0)
    committedOrigin = final ? actual.location : nil
    writes += 1
  }
  func mark(_ text: String, replacing range: NSRange) { write(text, replacing: range, final: false) }
  func insert(_ text: String, replacing range: NSRange) { write(text, replacing: range, final: true) }
  func appendManually(_ text: String) {
    document += text; actualMarked = NSRange(location: NSNotFound, length: 0)
    actualSelection = NSRange(location: document.utf16.count, length: 0); committedOrigin = nil
  }
}

@main struct InlineDeliveryTest {
  @MainActor static func main() async {
    // Exact observed terminal trace: caret stays at the beginning of our mark.
    let terminal = InlineHost(prefix: String(repeating: "x", count: 10308)), editing = VoiceEditing()
    terminal.caretAtStart = true; terminal.unreadable = true
    precondition(editing.begin(terminal))
    for text in ["你", "你好", "你好，这是持续输入🙂", "你好，这是持续输入🙂，并非只有第一个字"] {
      let accepted = await editing.receiveConfirmed(text, final: false)
      precondition(accepted && editing.validate() && terminal.document.hasSuffix(text))
    }
    let terminalFinal = await editing.receiveConfirmed("你好，这是持续输入🙂，完成。", final: true)
    precondition(terminalFinal && editing.validate())
    print("PASS: terminal caret at marked-range start supports all partial revisions and final commit")

    // Exact iTerm trace: 8 UTF-16 units advance the terminal caret by 16 cells.
    // Repeated utterances must anchor each new mark using the actual host range.
    let cells = InlineHost(prefix: String(repeating: "x", count: 5058)), cellEdit = VoiceEditing()
    cells.terminalCells = true; cells.caretAtStart = true; cells.unreadable = true
    precondition(cellEdit.begin(cells))
    var cellExpected = cells.document
    for index in 0..<12 {
      let text = "终端第\(index)段🙂。"
      let partial = await cellEdit.receiveConfirmed(String(text.dropLast()), final: false)
      precondition(partial)
      cells.committedCellCaret = 5058 + (index+1)*16
      let final = await cellEdit.receiveConfirmed(text, final: true)
      precondition(final && cellEdit.validate())
      cellExpected += text; precondition(cells.document == cellExpected)
    }
    cellEdit.protect(); cells.appendManually("[KEEP]"); cells.committedCellCaret = nil
    precondition(cellEdit.resumeAfterManualEdit())
    let cellResume = await cellEdit.receiveConfirmed("继续说话", final: false)
    cells.committedCellCaret = 5400
    let cellFinal = await cellEdit.receiveConfirmed("继续说话。", final: true)
    precondition(cellResume && cellFinal && cells.document == cellExpected+"[KEEP]继续说话。")
    // Host policy alone never bypasses the preceding native ownership proof.
    let noProof = InlineHost(), proofEdit = VoiceEditing()
    noProof.terminalCells = true; noProof.unreadable = true; noProof.committedCellCaret = 100
    precondition(proofEdit.begin(noProof))
    let noProofFinal = await proofEdit.receiveConfirmed("无组字证明", final: true)
    precondition(!noProofFinal && noProof.writes == 1)
    let ordinary = InlineHost(prefix: "原有"), ordinaryEdit = VoiceEditing()
    ordinary.unreadable = true
    precondition(ordinaryEdit.begin(ordinary))
    let ordinaryPartial = await ordinaryEdit.receiveConfirmed("普通宿主", final: false)
    precondition(ordinaryPartial)
    ordinary.committedCellCaret = 200
    let ordinaryFinal = await ordinaryEdit.receiveConfirmed("普通宿主。", final: true)
    precondition(!ordinaryFinal && ordinary.document == "原有普通宿主。")
    print("PASS: iTerm cell-coordinate commits support 12 pause/resume segments and manual edits; final-only and ordinary-host unknown carets remain rejected")

    // Observed Codex contract: document-based mark, fragment-relative final caret.
    let prefix = "已有文字🙂" + String(repeating: "字", count: 69)
    let web = InlineHost(prefix: prefix), continuous = VoiceEditing()
    web.relativeFinal = true; web.unreadable = true
    precondition(continuous.begin(web))
    var expected = prefix
    for index in 0..<24 {
      let text = "第\(index)段🙂。"
      let partial = await continuous.receiveConfirmed(String(text.dropLast()), final: false)
      let final = await continuous.receiveConfirmed(text, final: true)
      precondition(partial && final && continuous.validate())
      expected += text; precondition(web.document == expected)
    }
    continuous.protect(); web.appendManually("[KEEP]")
    precondition(continuous.resumeAfterManualEdit())
    let resumed = await continuous.receiveConfirmed("继续输入", final: false)
    let resumedFinal = await continuous.receiveConfirmed("继续输入。", final: true)
    precondition(resumed && resumedFinal && web.document == expected+"[KEEP]继续输入。")
    print("PASS: 24 fragment-relative final commits rebase later compositions correctly and preserve manual [KEEP]")

    // A real write can succeed while its acknowledgement is unavailable.
    let uncertain = InlineHost(), unconfirmed = VoiceEditing()
    uncertain.unreadable = true; uncertain.exposeMarks = false
    precondition(unconfirmed.begin(uncertain))
    var transcript = VoiceTranscript()
    transcript.update(text: "已经写入", start: 0, end: 1, final: false)
    transcript.inlineWriteAttempted()
    let accepted = await unconfirmed.receiveConfirmed("已经写入", final: false)
    precondition(!accepted && uncertain.document == "已经写入" && uncertain.writes == 1)
    precondition(!transcript.allowsAutomaticFinalInsertion && transcript.remaining == "已经写入")
    print("PASS: successful-but-unacknowledged write remains reviewable and is ineligible for automatic replay at stop")

    let sealed = InlineHost(), seal = VoiceEditing()
    precondition(seal.begin(sealed))
    let partial = await seal.receiveConfirmed("你好", final: false)
    precondition(partial)
    let visible = seal.ownedMarkedText!; precondition(seal.finish())
    var tail = VoiceTranscript(); tail.inlineWriteAttempted()
    tail.update(text: visible, start: 0, end: 1, final: false)
    tail.deliveredPrefix(start: 0, text: visible)
    tail.update(text: "你好世界", start: 0, end: 2, final: true)
    precondition(sealed.document == "你好" && tail.remaining == "世界" && !tail.allowsAutomaticFinalInsertion)
    tail.delivered(start: 0); tail.update(text: "你好世界", start: 0, end: 2, final: true)
    precondition(tail.wasDelivered(start: 0) && tail.remaining.isEmpty)
    print("PASS: focus transition seals visible prefix once, previews only the tail, and ignores delivered final replays")

    let original = InlineHost(prefix: "原有"), reconnect = VoiceEditing()
    precondition(reconnect.begin(original))
    let owned = await reconnect.receiveConfirmed("当前识别", final: false)
    precondition(owned)
    let replacement = InlineHost()
    replacement.document = original.document; replacement.actualSelection = original.actualSelection; replacement.actualMarked = original.actualMarked
    precondition(reconnect.rebindComposition(to: replacement))
    let continued = await reconnect.receiveConfirmed("当前识别继续", final: false)
    precondition(continued && replacement.document == "原有当前识别继续")
    reconnect.protect(); replacement.appendManually("[MANUAL]")
    precondition(!reconnect.rebindComposition(to: original))
    var grace = VoiceContextContinuity()
    precondition(grace.observe(sameApplication: true, attached: false, now: 10) == .waiting)
    precondition(grace.observe(sameApplication: true, attached: true, now: 10.1) == .ready)
    precondition(grace.observe(sameApplication: true, attached: false, now: 11) == .waiting)
    precondition(grace.observe(sameApplication: true, attached: false, now: 11.4) == .preview)
    precondition(grace.observe(sameApplication: false, attached: true, now: 12) == .preview)
    print("PASS: short native-controller recreation retains verified ownership; manual edits and real app changes revoke it")
  }
}
