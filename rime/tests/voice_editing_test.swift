import AppKit

@MainActor final class Host: VoiceTextHost {
  let view: NSTextView
  init(view: NSTextView? = nil) { self.view = view ?? NSTextView() }
  var emulateIMK = false
  var reportsMarkedSelection: Bool { emulateIMK }
  var selection: NSRange { emulateIMK && view.hasMarkedText() ? view.markedRange() : view.selectedRange() }
  var marked: NSRange { view.markedRange() }
  func text(in range: NSRange) -> String? {
    guard NSMaxRange(range) <= view.string.utf16.count else { return nil }
    return (view.string as NSString).substring(with: range)
  }
  func mark(_ text: String, replacing range: NSRange) {
    view.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: range)
  }
  func insert(_ text: String, replacing range: NSRange) { view.insertText(text, replacementRange: range) }
}

@main struct Test {
  @MainActor static func main() {
    let host = Host(), edit = VoiceEditing()
    host.view.string = "原文🙂"; host.view.setSelectedRange(NSRange(location: 4, length: 0))
    assert(edit.begin(host))
    assert(edit.receive("你", final: false)); assert(host.view.hasMarkedText())
    assert(edit.receive("你好", final: false)); assert(host.view.string == "原文🙂你好")
    assert(edit.receive("你好。", final: true)); assert(!host.view.hasMarkedText())
    assert(edit.receive("第二句。", final: true)); assert(edit.undo())
    assert(host.view.string == "原文🙂你好。"); assert(edit.undo())
    assert(host.view.string == "原文🙂")
    print("PASS: actual NSTextView partial revision, finalization, UTF-16 and successive undo")

    host.view.setSelectedRange(NSRange(location: 0, length: 2))
    assert(edit.begin(host)); assert(edit.receive("替换", final: false))
    edit.finish(discard: true); assert(host.view.string == "原文🙂")
    assert(edit.begin(host)); assert(edit.receive("替换", final: true)); assert(edit.undo())
    assert(host.view.string == "原文🙂")
    print("PASS: selection replacement and cancel/undo restore selected original")

    host.view.setSelectedRange(NSRange(location: 4, length: 0))
    assert(edit.begin(host)); assert(edit.receive("语音", final: false))
    edit.protect(); host.view.insertText("手动", replacementRange: NSRange(location: NSNotFound, length: 0))
    assert(!edit.receive("错误覆盖", final: false)); assert(!edit.receive("错误覆盖", final: true))
    assert(host.view.string == "原文🙂语音手动"); assert(!edit.undo())
    assert(edit.receive("新段", final: true)); assert(host.view.string == "原文🙂语音手动新段")
    print("PASS: manual input seals owned text, drops delayed current results, resumes next segment")

    host.view.setSelectedRange(NSRange(location: 0, length: 0))
    assert(!edit.undo()); assert(!edit.receive("危险", final: true))
    assert(!host.view.string.contains("危险"))
    assert(edit.begin(host)); assert(edit.receive("已确认", final: true))
    host.view.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 3), with: "已修改")
    assert(!edit.undo()); assert(host.view.string.hasPrefix("已修改"))
    print("PASS: changed caret or externally changed text blocks overwrite and undo")

    let proxy = Host(), proxyEditing = VoiceEditing()
    proxy.emulateIMK = true
    assert(proxyEditing.begin(proxy)); assert(proxyEditing.receive("你", final: false))
    assert(proxyEditing.receive("你好", final: false)); assert(proxyEditing.validate())
    assert(proxyEditing.receive("你好。", final: true)); assert(proxyEditing.undo())
    assert(proxy.view.string.isEmpty)
    print("PASS: IMK whole-marked selection supports repeated revision and strict final undo")
    let durable = Host(), durableEditing = VoiceEditing()
    assert(durableEditing.begin(durable)); assert(durableEditing.receive("重新连接", final: true))
    let replacement = Host(view: durable.view)
    assert(durableEditing.rebindUndo(to: replacement)); assert(durableEditing.undo())
    assert(durable.view.string.isEmpty)
    assert(durableEditing.begin(durable)); assert(durableEditing.receive("已确认", final: true))
    durable.view.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 3), with: "已修改")
    assert(!durableEditing.rebindUndo(to: replacement))
    print("PASS: reconnected host can undo only exact unedited text and caret")
    let copied = Host(), copiedEditing = VoiceEditing()
    assert(copiedEditing.begin(copied)); assert(copiedEditing.receive("可复制", final: true))
    let copyCaret = copied.view.selectedRange()
    copied.view.setSelectedRange(NSRange(location: 0, length: 3))
    assert(copied.text(in: copied.selection) == "可复制")
    copied.view.setSelectedRange(copyCaret)
    assert(copiedEditing.undo()); assert(copied.view.string.isEmpty)
    print("PASS: selecting and reading for copy preserves verified voice undo")
    let focused = Host(), focusEditing = VoiceEditing()
    assert(focusEditing.begin(focused)); assert(focusEditing.receive("已上屏", final: true))
    assert(focusEditing.receive("暂定尾部", final: false)); focusEditing.finish(discard: true)
    assert(focused.view.string == "已上屏")
    let returning = Host(view: focused.view)
    assert(focusEditing.rebindUndo(to: returning)); assert(focusEditing.undo())
    assert(focused.view.string.isEmpty)
    print("PASS: discarding a provisional tail on focus change preserves confirmed-segment undo")
    let newer = Host(); newer.view.string = "其他文档"
    assert(edit.begin(newer)); assert(!edit.undo()); assert(newer.view.string == "其他文档")
    print("PASS: new host retires old-document undo permission")
    if CommandLine.arguments.count > 1 {
      let lines = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).split(separator: "\n")
      let live = Host(), pipeline = VoiceEditing()
      assert(pipeline.begin(live))
      var partials = 0, finals = 0
      for line in lines {
        let event = try! JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
        if event["type"] as? String != "result" { continue }
        let text = event["text"] as! String, final = event["final"] as! Bool
        assert(pipeline.receive(text, final: final))
        if final { finals += 1 } else { partials += 1 }
      }
      assert(partials > 1 && finals > 0)
      assert(live.view.string.contains("本地语音输入测试"))
      assert(live.view.string.contains("手动编辑和撤回"))
      assert(pipeline.undo()); assert(live.view.string.isEmpty)
      print("PASS: actual Apple recognition events rendered and undone; \(partials) partials, \(finals) finals")
    }
  }
}
