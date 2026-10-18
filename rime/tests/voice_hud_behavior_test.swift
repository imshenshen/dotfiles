import AppKit

@main struct HUDBehaviorTest {
  @MainActor static func main() async {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let screens = NSScreen.screens
    precondition(!screens.isEmpty)
    let hud = VoiceHUD()
    defer { hud.hide() }
    let editor = (hud.panel.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!.documentView as! NSTextView)
    var cancelled = 0
    hud.onCancel = { cancelled += 1; hud.hide() }
    // Inject our own anchor: never inspect or type into another app's UI.
    for screen in screens {
      hud.hide()
      hud.inputAnchor = { CGRect(x: screen.frame.midX, y: screen.frame.midY, width: 1, height: 20) }
      hud.show("公开测试 · 未录音", recording: true)
      precondition(hud.panel.isVisible)
      precondition(screen.visibleFrame.contains(hud.panel.frame))
      precondition(abs(hud.panel.frame.midX-screen.visibleFrame.midX) < 1)
      let bottom = hud.panel.frame.minY
      hud.preview("公开测试文字，用于检查浮条向上展开。")
      precondition(hud.panel.frame.minY == bottom)
      precondition(screen.visibleFrame.contains(hud.panel.frame))
    }
    print("PASS: actual HUD window anchors and expands on all \(screens.count) attached display(s)")
    if screens.count > 1 {
      let destination = screens[0]
      hud.inputAnchor = { CGRect(x: destination.frame.midX, y: destination.frame.midY, width: 1, height: 20) }
      hud.followInputScreen(force: true)
      precondition(destination.visibleFrame.contains(hud.panel.frame))
      print("PASS: a visible recording HUD follows an input anchor moved to the other display")
    }
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
      windowNumber: hud.panel.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
      isARepeat: false, keyCode: 53)!
    precondition(hud.panel.performKeyEquivalent(with: escape))
    precondition(cancelled == 1 && !hud.panel.isVisible)
    precondition(editor.string.isEmpty, "Cancelling a preview must clear its text, not just hide the panel")
    hud.show("下一轮听写", recording: true)
    precondition(editor.string.isEmpty && hud.panel.frame.width == 216 && hud.panel.frame.height == 56)
    hud.preview("本轮内容应在状态更新时保留")
    hud.show("正在完成本轮听写", recording: true)
    precondition(editor.string == "本轮内容应在状态更新时保留")
    hud.hide()
    hud.show("又一轮听写", recording: true)
    precondition(editor.string.isEmpty && !hud.hasPendingResult)
    precondition(hud.panel.frame.width == 216 && hud.panel.frame.height == 56)
    print("PASS: cancel/hide then restart clears previous preview, while same-recording status updates preserve current text")
    hud.showResult("公开测试结果，不复制也不发送。")
    hud.show("请先处理上一段听写结果", recording: false)
    precondition(hud.hasPendingResult && editor.string == "公开测试结果，不复制也不发送。")
    precondition(hud.hasPendingResult)
    precondition(hud.panel.performKeyEquivalent(with: escape))
    precondition(!hud.panel.isVisible && !hud.hasPendingResult && cancelled == 1)
    print("PASS: recording Escape cancels once; result Escape closes and clears pending result without clipboard writes")
    hud.show("再次开始", recording: true)
    precondition(hud.panel.isVisible && !hud.hasPendingResult && editor.string.isEmpty)
    precondition(editor.selectedRange() == NSRange(location: 0, length: 0))
    hud.hide()
    await testRewrite()
    testHistory()
    print("PASS: all HUD tests completed")
  }
  @MainActor static func testRewrite() async {
    let hud = VoiceHUD()
    defer { hud.hide() }
    let editor = (hud.panel.contentView!.subviews.compactMap { $0 as? NSScrollView }.first!.documentView as! VoiceCopyTextView)
    let source = "已经上屏的第一句。仍在浮窗的第二句。"
    hud.show("公开测试 · 未录音", recording: true)
    hud.setRewriteSource(source)
    var requested: VoiceRewriteLevel?
    hud.onRewrite = { requested = $0 }
    let footer = hud.panel.contentView!.subviews.first { $0.subviews.contains { $0 is NSPopUpButton } }!
    let button = footer.subviews.compactMap { $0 as? NSPopUpButton }.first!
    let spinner = footer.subviews.compactMap { $0 as? NSProgressIndicator }.first!
    precondition(spinner.isHidden && spinner.style == .spinning && spinner.isIndeterminate)
    let tidy = button.itemArray.first { $0.tag == 2 }!
    precondition(tidy.isEnabled && editor.string.isEmpty, "Rewrite must be available even when all text is inline")
    precondition((button.cell as! NSPopUpButtonCell).arrowPosition == .noArrow)
    func key(_ char: String, flags: NSEvent.ModifierFlags = .command, repeatKey: Bool = false) -> NSEvent {
      NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
        windowNumber: hud.panel.windowNumber, context: nil, characters: char, charactersIgnoringModifiers: char,
        isARepeat: repeatKey, keyCode: char == "t" ? 17 : 15)!
    }
    hud.panel.resignKey()
    precondition(!hud.panel.performKeyEquivalent(with: key("t")) && requested == nil, "A HUD without keyboard focus must not consume app shortcuts")
    let click = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 210, y: 54), modifierFlags: [],
      timestamp: 0, windowNumber: hud.panel.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    hud.panel.sendEvent(click)
    precondition(hud.panel.isKeyWindow, "Clicking the recording HUD must permit local shortcuts")
    NSApp.sendEvent(key("t"))
    precondition(requested == .tidy)
    precondition(hud.panel.performKeyEquivalent(with: key("r")) && requested == .restructure)
    precondition(VoiceHUDPanel.rewriteLevel(for: key("t", flags: [.command, .shift])) == nil)
    precondition(hud.panel.performKeyEquivalent(with: key("t", repeatKey: true)) && requested == .restructure)
    requested = nil
    hud.menuWillOpen(button.menu!)
    precondition(hud.containsInteraction(at: CGPoint(x: -9999, y: -9999)), "Our popup must not revoke host ownership")
    hud.menuDidClose(button.menu!)
    NSApp.sendAction(tidy.action!, to: tidy.target, from: tidy)
    precondition(requested == .tidy)
    var received = ""
    var levels: [VoiceRewriteLevel] = []
    hud.rewrite = { text, level in received = text; levels.append(level); return level == .tidy ? "整理后的完整两句话。" : "三级重组后的全文。" }
    hud.performRewrite(source, level: .tidy)
    precondition(!spinner.isHidden && !editor.isEditable, "A rewrite must show loading immediately")
    for _ in 0..<50 { if editor.string == "整理后的完整两句话。" { break }; try? await Task.sleep(nanoseconds: 10_000_000) }
    precondition(received == source && editor.string == "整理后的完整两句话。" && editor.isEditable)
    precondition(spinner.isHidden, "Loading must stop on success")
    NSApp.sendEvent(key("r"))
    for _ in 0..<50 { if editor.string == "三级重组后的全文。" { break }; try? await Task.sleep(nanoseconds: 10_000_000) }
    precondition(levels == [.tidy, .restructure] && received == source && editor.string == "三级重组后的全文。")
    var copied = ""
    editor.writeClipboard = { copied = $0; return true }; editor.copyAll()
    precondition(copied == "三级重组后的全文。" && !hud.panel.isVisible)
    hud.rewrite = { _, _ in throw VoiceRewriteError.http(401) }
    hud.performRewrite(source, level: .restructure)
    for _ in 0..<50 { if editor.isEditable { break }; try? await Task.sleep(nanoseconds: 10_000_000) }
    precondition(editor.string == source && hud.hasPendingResult, "Network failure must preserve the whole original")
    precondition(spinner.isHidden, "Loading must stop on failure")
    var completion: CheckedContinuation<String, Never>?
    hud.rewrite = { _, _ in await withCheckedContinuation { completion = $0 } }
    hud.performRewrite(source, level: .tidy)
    for _ in 0..<50 { if completion != nil { break }; try? await Task.sleep(nanoseconds: 10_000_000) }
    precondition(completion != nil)
    precondition(!spinner.isHidden, "Loading must remain visible while the request is pending")
    precondition(hud.panel.performKeyEquivalent(with: key("r")), "Busy rewrite shortcut must be consumed without launching another request")
    hud.hide(); hud.show("新一轮", recording: true)
    precondition(spinner.isHidden, "Closing a pending rewrite must clear loading for the next recording")
    completion?.resume(returning: "上一轮迟到结果")
    try? await Task.sleep(nanoseconds: 30_000_000)
    precondition(editor.string.isEmpty && !hud.hasPendingResult)
    print("PASS: focused recording/result HUD Cmd+T/Cmd+R, no unfocused interception/repeat requests, star without arrow, whole-session preview, loading lifecycle on success/failure/cancel/restart, failure preservation and late-result rejection")
  }
  @MainActor static func testHistory() {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = VoiceHistoryStore(url: directory.appendingPathComponent("history.json"))
    let text = "误按 Esc 后仍可找回的公开测试文字🙂"
    store.update(id: "test", startedAt: Date(), text: text, state: "cancelled")
    let preferences = VoiceHistoryPreferences(store: store)
    var copied = ""
    preferences.writeClipboard = { copied = $0 }
    preferences.show()
    let window = NSApp.windows.first { $0.title == "听写历史" }!
    defer { window.close() }
    let root = window.contentView!
    let scrolls = root.subviews.compactMap { $0 as? NSScrollView }
    let table = scrolls.compactMap { $0.documentView as? NSTableView }.first!
    let detail = scrolls.compactMap { $0.documentView as? NSTextView }.first!
    precondition(table.numberOfRows == 1 && detail.string == text && !detail.isEditable && detail.isSelectable)
    let menu = root.subviews.compactMap { $0 as? NSPopUpButton }.first!
    var rewritten: String?
    preferences.rewriteText = { source, level in precondition(level == .restructure); rewritten = source }
    let deep = menu.itemArray.first { $0.tag == 3 }!
    NSApp.sendAction(deep.action!, to: deep.target, from: deep)
    precondition(rewritten == text)
    let buttons = root.subviews.compactMap { $0 as? NSButton }
    buttons.first { $0.title == "复制全文" }!.performClick(nil)
    precondition(copied == text)
    buttons.first { $0.title == "删除此条" }!.performClick(nil)
    precondition(store.entries.isEmpty)
    print("PASS: native history window displays cancelled text, selects full record, copies via isolated clipboard and deletes the record")
  }
}
