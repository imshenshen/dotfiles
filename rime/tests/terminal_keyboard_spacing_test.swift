import AppKit
import InputMethodKit
enum VoiceSettings { static let mixedSpacing = true }
enum RimeVoiceUI {}

// Replay the observed native protocol: all reads return padding, while the
// grid caret advances two cells per Han character and one per ASCII character.
final class PaddingTerminal: NSObject, IMKTextInput {
  var document = ""
  var caret = 1606
  var marked = NSRange(location:1606,length:0)
  var bundle = "com.googlecode.iterm2"
  var following: String?
  var afterCommit: String?
  var previous: String?
  var commitBias = 0
  var staleSelection: Int?
  var beforeOverride: String?
  var beforeOverrideAt: Int?
  var replacements: [NSRange] = []
  func insertText(_ string: Any!, replacementRange: NSRange) {
    let text = string as! String
    replacements.append(replacementRange); document += text
    caret += text.reduce(0) { $0 + (VoiceTextFormatter.han($1) ? 2 : 1) } + commitBias
    commitBias = 0
    marked.length = 0 // iTerm keeps the old mark's location after commit.
  }
  func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
    marked = NSRange(location:caret,length:(string as! String).utf16.count)
  }
  func selectedRange() -> NSRange {
    if let staleSelection { return NSRange(location:staleSelection,length:0) }
    return NSRange(location:caret,length:0)
  }
  func markedRange() -> NSRange { marked }
  func attributedSubstring(from range: NSRange) -> NSAttributedString! {
    if let previous, range.location + range.length == caret {
      self.previous = nil
      return NSAttributedString(string:previous)
    }
    if let beforeOverride, let beforeOverrideAt, range.location + range.length == beforeOverrideAt {
      self.beforeOverride = nil
      return NSAttributedString(string:beforeOverride)
    }
    if range.location == caret, range.length == 2, let following { return NSAttributedString(string:following) }
    if range.location == caret + 4, range.length == 2, let afterCommit {
      return NSAttributedString(string:afterCommit)
    }
    return NSAttributedString(string:String(repeating:" ",count:range.length))
  }
  func length() -> Int { NSNotFound }
  func characterIndex(for point: NSPoint, tracking mappingMode: IMKLocationToOffsetMappingMode, inMarkedRange: UnsafeMutablePointer<ObjCBool>!) -> Int { NSNotFound }
  func attributes(forCharacterIndex index: Int, lineHeightRectangle lineRect: UnsafeMutablePointer<NSRect>!) -> [AnyHashable:Any]! { [:] }
  func validAttributesForMarkedText() -> [Any]! { [] }
  func overrideKeyboard(withKeyboardNamed keyboardUniqueName: String!) {}
  func selectMode(_ modeIdentifier: String!) {}
  func supportsUnicode() -> Bool { true }
  func bundleIdentifier() -> String! { bundle }
  func windowLevel() -> CGWindowLevel { 0 }
  func supportsProperty(_ property: TSMDocumentPropertyTag) -> Bool { false }
  func uniqueClientIdentifierString() -> String! { "owned-test-client" }
  func string(from range: NSRange, actualRange: NSRangePointer!) -> String! { nil }
  func firstRect(forCharacterRange aRange: NSRange, actualRange: NSRangePointer!) -> NSRect { .zero }
}

@main struct TerminalKeyboardTest {
  @MainActor static func main() {
    let native = NSRange(location:NSNotFound,length:0)
    func key(_ text: String, modifiers: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown, code: UInt16 = 0) -> NSEvent {
      NSEvent.keyEvent(with:type,location:.zero,modifierFlags:modifiers,timestamp:0,windowNumber:0,context:nil,
        characters:text,charactersIgnoringModifiers:text,isARepeat:false,keyCode:code)!
    }
    func controller() -> RimeDirectTextInput {
      let value = RimeDirectTextInput()
      value.formatter = { VoiceTextFormatter(spaces:true,entries:[.init(output:"AI助手",code:"ai",weight:"",spoken:"")]) }
      return value
    }
    precondition(RimeDirectTextInput.isUppercaseDirect(key("A",modifiers:.shift)))
    precondition(RimeDirectTextInput.isUppercaseDirect(key("A",modifiers:.capsLock)))
    precondition(!RimeDirectTextInput.isUppercaseDirect(key("a")))
    precondition(!RimeDirectTextInput.isUppercaseDirect(key("A",modifiers:.command)))
    precondition(!RimeDirectTextInput.isUppercaseDirect(key("1",modifiers:.shift)))
    func commit(_ text: String, _ client: PaddingTerminal, _ input: RimeDirectTextInput, trigger: String = " ", code: UInt16 = 0) {
      client.marked = NSRange(location:client.caret,length:4)
      input.beginEvent(key(trigger,code:code),composing:true)
      let formatted = input.formatCommittedText(text,client:client)
      client.insertText(formatted,replacementRange:native)
      input.didCommit(formatted,client:client)
      precondition(!input.handle(key(trigger,code:code),client:client,enabled:false))
    }
    func type(_ text: String, _ client: PaddingTerminal, _ input: RimeDirectTextInput) {
      for character in text {
        let event = key(String(character)); input.beginEvent(event,composing:false)
        if !input.handle(event,client:client,enabled:true) { client.insertText(String(character),replacementRange:native) }
      }
    }
    let client = PaddingTerminal(), input = controller()
    commit("中文",client,input)
    input.beginEvent(key("",modifiers:.shift,type:.flagsChanged),composing:false)
    type("mac",client,input)
    precondition(client.document == "中文 mac",client.document)
    precondition(client.replacements.allSatisfy { $0 == native }, "Context must never authorize deleting existing terminal text")
    let candidate = PaddingTerminal(), candidateInput = controller()
    commit("中文",candidate,candidateInput)
    for character in "mac" { candidateInput.beginEvent(key(String(character)),composing:true); _ = candidateInput.handle(key(String(character)),client:candidate,enabled:false) }
    commit("mac",candidate,candidateInput)
    precondition(candidate.document == "中文 mac",candidate.document)
    for (trigger,code) in [("\r",UInt16(36)),("\u{3}",UInt16(76))] {
      let raw = PaddingTerminal(), rawInput = controller()
      commit("中文",raw,rawInput)
      for character in "mac" { rawInput.beginEvent(key(String(character)),composing:true); _ = rawInput.handle(key(String(character)),client:raw,enabled:false) }
      commit("mac",raw,rawInput,trigger:trigger,code:code)
      guard raw.document == "中文 mac" else { print("FAIL: composing Return/Enter discarded the prefix context"); exit(1) }
      rawInput.beginEvent(key(trigger,code:code),composing:false)
      // Even if a terminal redraw leaves the same caret, a real command Enter
      // must not allow the next command to inherit the preceding Chinese tail.
      let next = rawInput.formatCommittedText("下文",client:raw)
      precondition(next == "下文")
    }
    let reverse = PaddingTerminal(), reverseInput = controller()
    type("mac",reverse,reverseInput); commit("中文",reverse,reverseInput)
    precondition(reverse.document == "mac 中文",reverse.document)
    let manual = PaddingTerminal(), manualInput = controller()
    commit("中文",manual,manualInput)
    for _ in 0..<2 { manualInput.beginEvent(key(" "),composing:false); manual.insertText(" ",replacementRange:native) }
    type("mac",manual,manualInput)
    precondition(manual.document == "中文  mac",manual.document)
    let moved = PaddingTerminal(), movedInput = controller()
    commit("中文",moved,movedInput); moved.caret += 10
    type("m",moved,movedInput); precondition(moved.document == "中文m")
    let erased = PaddingTerminal(), erasedInput = controller()
    commit("中文",erased,erasedInput)
    erasedInput.beginEvent(key("\u{7f}"),composing:false)
    erased.document = ""; erased.caret = 1606
    type("mac",erased,erasedInput); precondition(erased.document == "mac")
    let dictionary = PaddingTerminal(), dictionaryInput = controller()
    commit("中文",dictionary,dictionaryInput); commit("AI助手",dictionary,dictionaryInput)
    precondition(dictionary.document == "中文 AI助手",dictionary.document)
    let other = PaddingTerminal(), otherInput = controller(); other.bundle = "example.ordinary"
    commit("中文",other,otherInput); type("mac",other,otherInput)
    precondition(other.document == "中文mac", "Ordinary clients must not use the terminal fallback")
    let oldClient = PaddingTerminal(), reusedInput = controller()
    commit("中文",oldClient,reusedInput)
    let newClient = PaddingTerminal(); newClient.caret = oldClient.caret
    type("mac",newClient,reusedInput)
    precondition(newClient.document == "mac", "A different client at the same grid caret must not inherit context")
    let gapClient = PaddingTerminal(), gapInput = controller(); gapClient.following = "你好"
    commit(String(repeating:"中",count:32),gapClient,gapInput)
    type("ma",gapClient,gapInput)
    precondition(gapClient.replacements.allSatisfy { $0 == native }, "An unreadable owned prefix must never authorize deleting a trailing gap")
    // Fast commits can read stale Latin cells to the right of the grid caret.
    // That buffer must not add a trailing space; the next direct key adds its
    // own verified leading gap.
    let staleAfter = PaddingTerminal(), staleAfterInput = controller()
    staleAfter.afterCommit = "mac"
    commit("中文",staleAfter,staleAfterInput)
    precondition(staleAfter.document == "中文", "Trailing space from stale screen cells: \(staleAfter.document)")
    type("mac",staleAfter,staleAfterInput)
    precondition(staleAfter.document == "中文 mac",staleAfter.document)
    let upperClient = PaddingTerminal(), upperInput = controller()
    commit("中文",upperClient,upperInput)
    let upperEvent = key("A",modifiers:.shift)
    precondition(RimeDirectTextInput.isUppercaseDirect(upperEvent))
    precondition(upperInput.handle(upperEvent,client:upperClient,enabled:true))
    precondition(upperClient.document == "中文 A",upperClient.document)
    // A leading-gap commit can leave iTerm one grid cell ahead of the width
    // projection. The post-insert caret, not the projection, owns the tail.
    let shifted = PaddingTerminal(), shiftedInput = controller()
    shifted.previous = "o"
    shifted.commitBias = 1
    commit("为什么",shifted,shiftedInput)
    let shiftedEvent = key("A",modifiers:.shift)
    precondition(shiftedInput.handle(shiftedEvent,client:shifted,enabled:true))
    precondition(shifted.document == " 为什么 A",shifted.document)
    // iTerm can still report the pre-insert caret immediately after insertText.
    // Keep the projection as a second candidate until the next direct key.
    let stale = PaddingTerminal(), staleInput = controller()
    stale.previous = "o"
    stale.marked = NSRange(location:stale.caret,length:4)
    staleInput.beginEvent(key(" ",code:0),composing:true)
    let staleFormatted = staleInput.formatCommittedText("为什么",client:stale)
    let stalePreInsert = stale.caret
    stale.insertText(staleFormatted,replacementRange:native)
    stale.staleSelection = stalePreInsert
    staleInput.didCommit(staleFormatted,client:stale)
    stale.staleSelection = nil
    let staleEvent = key("A",modifiers:.shift)
    precondition(staleInput.handle(staleEvent,client:stale,enabled:true))
    precondition(stale.document == " 为什么 A",stale.document)
    // Return commits raw composing English without an eligible direct key.
    // The previous commit must be reconciled at this commit's range first.
    let ret = PaddingTerminal(), retInput = controller()
    ret.previous = "o"
    ret.marked = NSRange(location:ret.caret,length:4)
    retInput.beginEvent(key(" ",code:0),composing:true)
    let first = retInput.formatCommittedText("为什么",client:ret)
    let firstPreInsert = ret.caret
    ret.insertText(first,replacementRange:native)
    ret.staleSelection = firstPreInsert
    retInput.didCommit(first,client:ret)
    ret.staleSelection = nil
    let composing = key("t")
    retInput.beginEvent(composing,composing:true); _ = retInput.handle(composing,client:ret,enabled:false)
    ret.marked = NSRange(location:ret.caret,length:4)
    retInput.beginEvent(key("\r",code:36),composing:true)
    let second = retInput.formatCommittedText("test",client:ret)
    precondition(second == " test",second)
    ret.insertText(second,replacementRange:native)
    retInput.didCommit(second,client:ret)
    precondition(ret.document == " 为什么 test",ret.document)
    // Fast typing can report the next composition's marked range behind the
    // real caret. The before-read must use the caret, or the previous word is
    // misread as Latin and two Chinese words get a spurious space.
    let fast = PaddingTerminal(), fastInput = controller()
    fast.previous = "home"
    fast.marked = NSRange(location:fast.caret,length:4)
    fastInput.beginEvent(key(" ",code:0),composing:true)
    let fastFirst = fastInput.formatCommittedText("影响",client:fast)
    let fastPreInsert = fast.caret
    fast.insertText(fastFirst,replacementRange:native)
    fast.staleSelection = fastPreInsert
    fastInput.didCommit(fastFirst,client:fast)
    fast.staleSelection = nil
    fast.beforeOverride = "home"
    fast.beforeOverrideAt = fastPreInsert
    fast.marked = NSRange(location:fastPreInsert,length:4)
    fastInput.beginEvent(key(" ",code:0),composing:true)
    let fastSecond = fastInput.formatCommittedText("什么",client:fast)
    precondition(fastSecond == "什么",fastSecond)
    fast.insertText(fastSecond,replacementRange:native)
    fastInput.didCommit(fastSecond,client:fast)
    precondition(fast.document == " 影响什么",fast.document)
    print("PASS: native IMK padded-context replay, direct ASCII and candidate paths, Shift, reverse boundary, exact dictionary spans, manual spaces/delete/move, client isolation, insertion-only behavior, stale trailing cells, post-commit caret, raw Return commit, stale marked range")
  }
}
