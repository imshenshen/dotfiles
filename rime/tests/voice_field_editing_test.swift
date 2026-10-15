import AppKit
@MainActor final class TestEditor: NSTextView {
  var actions: [String] = []
  override func paste(_ sender: Any?) { actions.append("paste"); string = "PUBLIC-TEST-KEY" }
  override func copy(_ sender: Any?) { actions.append("copy") }
  override func cut(_ sender: Any?) { actions.append("cut") }
  override func selectAll(_ sender: Any?) { actions.append("all") }
}
@main struct FieldEditingTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let window = VoiceEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: .titled, backing: .buffered, defer: false)
    let editor = TestEditor(); window.contentView = editor
    precondition(window.makeFirstResponder(editor))
    for (key, code, action) in [("v", UInt16(9), "paste"), ("a", 0, "all"), ("c", 8, "copy"), ("x", 7, "cut")] {
      let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
        windowNumber: window.windowNumber, context: nil, characters: key, charactersIgnoringModifiers: key, isARepeat: false, keyCode: code)!
      precondition(window.performKeyEquivalent(with: event))
      precondition(editor.actions.last == action)
    }
    precondition(editor.string == "PUBLIC-TEST-KEY")
    print("PASS: credential window forwards Cmd+V/A/C/X to the native field editor without an Edit menu; test never reads/writes system clipboard")
  }
}
