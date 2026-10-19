import Foundation

@main struct DirectTextSpacingTest {
  struct Host {
    var document: NSString
    var caret: Int
    var spacing = DirectTextSpacing()
    let formatter = VoiceTextFormatter(spaces: true, entries: [])
    mutating func type(_ text: String) {
      let before = document.substring(with: NSRange(location: max(0, caret-32), length: min(32, caret)))
      let after = document.substring(with: NSRange(location: caret, length: min(2, document.length-caret)))
      let plan = spacing.insertion(text, at: NSRange(location: caret, length: 0), previous: before,
                                   following: after, formatter: formatter)
      let range = plan?.range ?? NSRange(location: caret, length: 0)
      let insertion = plan?.text ?? text
      document = document.replacingCharacters(in: range, with: insertion) as NSString
      caret = range.location + insertion.utf16.count
    }
  }
  static func main() {
    // Observed live iTerm trace: Chinese commit at 1606, next caret 1610,
    // but the screen-text getter returns 32 padding spaces for every key.
    let plain = VoiceTextFormatter(spaces:true, entries:[])
    var echo = TerminalCommittedContext(), direct = DirectTextSpacing()
    echo.sent("中文", at:1606)
    var terminalOutput = "中文", terminalCaret = 1610
    for key in "mac" {
      let before = echo.before(terminalCaret, host:String(repeating:" ",count:32))
      let plan = direct.insertion(String(key), at:NSRange(location:terminalCaret,length:0),
        previous:before, following:"  ", formatter:plain)
      let written = plan?.text ?? String(key)
      echo.sent(written, at:terminalCaret)
      terminalOutput += written; terminalCaret += written.utf16.count
    }
    precondition(terminalOutput == "中文 mac", terminalOutput)
    var candidate = TerminalCommittedContext()
    candidate.sent("中文",at:1620)
    precondition(plain.format("mac",previous:candidate.before(1624,host:"")) == " mac")
    candidate.reset(); candidate.sent("mac",at:100)
    precondition(plain.format("中文",previous:candidate.before(103,host:"  ")) == " 中文")
    candidate.sent("中文",at:200)
    precondition(candidate.before(205,host:" ") == " ", "A moved/wrapped caret must invalidate ownership")
    candidate.sent("中文",at:300); candidate.reset()
    precondition(candidate.before(304,host:" ") == " ", "Manual spaces, deletion, navigation and deactivation reset context")
    candidate.sent("中文",at:400)
    precondition(candidate.before(404,host:"x") == "x")
    precondition(candidate.before(404,host:"").isEmpty, "Conflicting readable host text revokes ownership")
    candidate.sent("🙂",at:500)
    precondition(candidate.before(502,host:"").isEmpty, "Unknown terminal widths cannot establish ownership")
    let exact = VoiceTextFormatter(spaces:true,entries:[.init(output:"AI助手",code:"ai",weight:"",spoken:"")])
    precondition(exact.format("AI助手",previous:"使用") == " AI助手")
    print("PASS: observed iTerm padded-context trace, continuous ASCII and Latin candidate commits, reverse boundary, caret mismatch, manual invalidation and unsupported widths")
    let formatterForTerminal = VoiceTextFormatter(spaces: true, entries: [])
    var reads: [NSRange] = []
    let terminalBefore = KeyboardSpacingContext.before(104, terminal: true) { range in
      reads.append(range)
      return range == NSRange(location:100, length:4) ? "中文" : nil
    }
    precondition(terminalBefore == "中文" && reads.count == 4)
    precondition(formatterForTerminal.format("mac", previous:terminalBefore) == " mac")
    var terminalSpacing = DirectTextSpacing()
    precondition(terminalSpacing.insertion("m", at:NSRange(location:104,length:0), previous:terminalBefore,
      following:"", formatter:formatterForTerminal)?.text == " m")
    precondition(formatterForTerminal.format("中文", previous:"mac") == " 中文")
    precondition(KeyboardSpacingContext.before(104, terminal:false) { $0.length == 4 ? "中文" : nil }.isEmpty)
    precondition(KeyboardSpacingContext.before(NSNotFound, terminal:true) { _ in preconditionFailure() }.isEmpty)
    precondition(KeyboardSpacingContext.before(104, terminal:true) { _ in " " } == " ", "Never trim a real user space")
    precondition(KeyboardSpacingContext.before(104, terminal:true) { _ in nil }.isEmpty, "Never guess unreadable terminal context")
    var prefix = Host(document: "你好", caret: 0)
    for key in "ceshi" { prefix.type(String(key)) }
    precondition(prefix.document == "ceshi 你好", prefix.document as String)
    var middle = Host(document: "前面你好", caret: 2)
    for key in "MacBook123" { middle.type(String(key)) }
    precondition(middle.document == "前面 MacBook123 你好", middle.document as String)
    var existing = Host(document: "你好", caret: 0)
    existing.type("c"); existing.spacing.reset() // User deliberately interrupts with a space.
    existing.type(" "); existing.type("e")
    precondition(existing.document == "c  e 你好", existing.document as String)
    var moved = Host(document: "你好再见", caret: 0)
    moved.type("c"); moved.caret = moved.document.length
    moved.type("e")
    precondition(moved.document == "c 你好再见 e", moved.document as String)
    var changed = Host(document: "你好", caret: 0)
    changed.type("c"); changed.document = "X 你好" // Same caret; another edit invalidates ownership.
    changed.type("e")
    precondition(changed.document == "X e 你好", changed.document as String)
    var long = Host(document: String(repeating: "中", count: 40) as NSString, caret: 0)
    for key in String(repeating: "a", count: 80) { long.type(String(key)) }
    precondition(long.document == (String(repeating: "a", count: 80) + " " + String(repeating: "中", count: 40)) as NSString)
    var off = DirectTextSpacing()
    precondition(off.insertion("c", at: NSRange(location: 0, length: 0), previous: "", following: "你好",
                               formatter: .init(spaces: false, entries: [])) == nil)
    let formatter = VoiceTextFormatter(spaces: true, entries: [.init(output: "AI助手", code: "ai", weight: "", spoken: "")])
    precondition(formatter.format("测试", following: "你好") == "测试")
    precondition(formatter.format("AI助手", following: "你好") == "AI助手")
    print("PASS: continuous ASCII insertion before Chinese, mixed case/digits, existing spaces, caret moves, external edits, long words, toggle off and committed Chinese/dictionary text")
  }
}
