import AppKit

@main struct HUDBehaviorTest {
  @MainActor static func main() {
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
    precondition(editor.string.isEmpty && hud.panel.frame.width == 180 && hud.panel.frame.height == 56)
    hud.preview("本轮内容应在状态更新时保留")
    hud.show("正在完成本轮听写", recording: true)
    precondition(editor.string == "本轮内容应在状态更新时保留")
    hud.hide()
    hud.show("又一轮听写", recording: true)
    precondition(editor.string.isEmpty && !hud.hasPendingResult)
    precondition(hud.panel.frame.width == 180 && hud.panel.frame.height == 56)
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
  }
}
