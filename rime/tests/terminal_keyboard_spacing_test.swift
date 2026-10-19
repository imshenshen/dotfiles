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
  var replacements: [NSRange] = []
  func insertText(_ string: Any!, replacementRange: NSRange) {
    let text = string as! String
    replacements.append(replacementRange); document += text
    caret += text.reduce(0) { $0 + (VoiceTextFormatter.han($1) ? 2 : 1) }
    marked.length = 0 // iTerm keeps the old mark's location after commit.
  }
  func setMarkedText(_ string: Any!, selectionRange: NSRange, replacementRange: NSRange) {
    marked = NSRange(location:caret,length:(string as! String).utf16.count)
  }
  func selectedRange() -> NSRange { NSRange(location:caret,length:0) }
  func markedRange() -> NSRange { marked }
  func attributedSubstring(from range: NSRange) -> NSAttributedString! {
    if range.location == caret, range.length == 2, let following { return NSAttributedString(string:following) }
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
    func commit(_ text: String, _ client: PaddingTerminal, _ input: RimeDirectTextInput, trigger: String = " ", code: UInt16 = 0) {
      client.marked = NSRange(location:client.caret,length:4)
      input.beginEvent(key(trigger,code:code),composing:true)
      let formatted = input.formatCommittedText(text,client:client)
      client.insertText(formatted,replacementRange:native)
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
    print("PASS: native IMK padded-context replay, direct ASCII and candidate paths, Shift, reverse boundary, exact dictionary spans, manual spaces/delete/move, client isolation, insertion-only behavior")
  }
}
