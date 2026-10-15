import AppKit

// Input methods have no normal Edit menu to dispatch these key equivalents.
// Use the native field editor so secure fields retain their normal protections.
@MainActor final class VoiceEditingWindow: NSWindow {
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection([.command, .shift, .control, .option])
    guard flags == .command || flags == [.command, .shift],
          let editor = firstResponder as? NSTextView else { return super.performKeyEquivalent(with: event) }
    let key = event.charactersIgnoringModifiers?.lowercased()
    if key == "z" {
      if flags.contains(.shift), editor.undoManager?.canRedo == true { editor.undoManager?.redo(); return true }
      if !flags.contains(.shift), editor.undoManager?.canUndo == true { editor.undoManager?.undo(); return true }
    }
    if flags == .command {
      let action: Selector?
      switch key {
      case "v": action = #selector(NSText.paste(_:))
      case "a": action = #selector(NSText.selectAll(_:))
      case "c": action = #selector(NSText.copy(_:))
      case "x": action = #selector(NSText.cut(_:))
      default: action = nil
      }
      if let action, NSApp.sendAction(action, to: editor, from: self) { return true }
    }
    return super.performKeyEquivalent(with: event)
  }
}

@MainActor final class VoiceCopyTextView: NSTextView {
  var resultAvailable: () -> Bool = { false }
  var copied: (() -> Void)?
  var writeClipboard: (String) -> Bool = { text in
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(text, forType: .string)
  }
  private func deliver(_ text: String) {
    guard !text.isEmpty, writeClipboard(text) else { return }
    copied?()
  }
  override func copy(_ sender: Any?) {
    guard resultAvailable() else { super.copy(sender); return }
    let range = selectedRange()
    if range.length > 0, range.location != NSNotFound, NSMaxRange(range) <= string.utf16.count {
      deliver((string as NSString).substring(with: range))
    } else { deliver(string) }
  }
  func copyAll() { if resultAvailable() { deliver(string) } }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if resultAvailable(), event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
       event.charactersIgnoringModifiers?.lowercased() == "c" {
      copy(nil); return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
