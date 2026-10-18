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
  var dismissed: (() -> Void)?
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
  override func cancelOperation(_ sender: Any?) {
    if resultAvailable() { dismissed?() } else { super.cancelOperation(sender) }
  }
  override func keyDown(with event: NSEvent) {
    if resultAvailable(), VoiceHUDPanel.isEscape(event) { cancelOperation(nil); return }
    super.keyDown(with: event)
  }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if resultAvailable(), VoiceHUDPanel.isEscape(event) { cancelOperation(nil); return true }
    if resultAvailable(), event.modifierFlags.intersection([.command, .shift, .control, .option]) == .command,
       event.charactersIgnoringModifiers?.lowercased() == "c" {
      copy(nil); return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

@MainActor final class VoiceHUDPanel: NSPanel {
  var editingResult = false
  var allowsRewriteFocus = false
  var onRewriteShortcut: ((Int) -> Void)?
  var onEscape: (() -> Void)?
  override var canBecomeKey: Bool { editingResult || allowsRewriteFocus }
  override func sendEvent(_ event: NSEvent) {
    // Showing the nonactivating HUD never steals focus. Only an actual click
    // in this panel opts into its local keyboard shortcuts.
    if event.type == .leftMouseDown, canBecomeKey {
      makeKey()
      if !editingResult { makeFirstResponder(nil) }
    }
    super.sendEvent(event)
  }
  static func rewriteLevel(for event: NSEvent) -> Int? {
    guard event.type == .keyDown,
          event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command else { return nil }
    switch event.charactersIgnoringModifiers?.lowercased() {
    case "t": return 2
    case "r": return 3
    default: return nil
    }
  }
  static func isEscape(_ event: NSEvent) -> Bool {
    event.type == .keyDown && event.keyCode == 53 &&
      event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
  }
  override func cancelOperation(_ sender: Any?) { onEscape?() }
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if Self.isEscape(event) { onEscape?(); return true }
    if isKeyWindow, canBecomeKey, let level = Self.rewriteLevel(for: event) {
      if !event.isARepeat { onRewriteShortcut?(level) }
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}
