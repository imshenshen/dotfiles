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
