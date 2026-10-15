import AppKit
@MainActor final class NativeOnlyHost: VoiceTextHost {
  let view = NSTextView()
  var selection: NSRange { view.selectedRange() }
  var marked: NSRange { view.markedRange() }
  func text(in range: NSRange) -> String? {
    guard NSMaxRange(range) <= view.string.utf16.count else { return nil }
    return (view.string as NSString).substring(with: range)
  }
  func mark(_ text: String, replacing range: NSRange) {
    let native = VoiceHostRange.replacement(range, selection: selection, marked: marked)
    guard native.location == NSNotFound else { return } // Emulate web clients rejecting explicit ranges.
    view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: native)
  }
  func insert(_ text: String, replacing range: NSRange) {
    let native = VoiceHostRange.replacement(range, selection: selection, marked: marked)
    guard native.location == NSNotFound else { return }
    view.insertText(text, replacementRange: native)
  }
}
@main struct NativeRangeTest {
  @MainActor static func main() {
    let host = NativeOnlyHost(), edit = VoiceEditing()
    host.view.string = "用户原文"; host.view.setSelectedRange(NSRange(location: 4, length: 0))
    precondition(edit.begin(host)); precondition(edit.receive("你", final: false))
    precondition(edit.receive("你好", final: false)); precondition(edit.receive("你好。", final: true))
    precondition(host.view.string == "用户原文你好。")
    let other = NSRange(location: 0, length: 2)
    precondition(VoiceHostRange.replacement(other, selection: host.selection, marked: host.marked) == other)
    edit.protect(); host.view.insertText("KEEP", replacementRange: NSRange(location: NSNotFound, length: 0))
    precondition(edit.resumeAfterManualEdit()); precondition(edit.receive("继续", final: true))
    precondition(host.view.string == "用户原文你好。KEEP继续")
    print("PASS: native current-composition replacement supports web-style hosts, with range ownership and manual-edit protection")
  }
}
