// Standalone synthetic UI fixture. Never reads or writes a personal dictionary.
import AppKit
@main struct DictionaryPreview {
  @MainActor static func main() {
    let app = NSApplication.shared; app.setActivationPolicy(.regular)
    let parent = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    parent.title = "豆包词库合并 · 合成验收"; parent.center(); parent.makeKeyAndOrderFront(nil)
    let label = NSTextField(labelWithString: "等待合并；仅使用合成数据，不写文件。")
    label.frame = NSRect(x: 24, y: 30, width: 750, height: 28); parent.contentView!.addSubview(label)
    let importer = DoubaoDictionaryImport(read: {
      .init(words: [.init(output: "松鼠桥接甲", code: "songshuqiaojiejia", platforms: 1),
                     .init(output: "松鼠桥接乙", code: "songshuqiaojieyi", platforms: 2),
                     .init(output: "MacBookPro", code: "macbookpro", platforms: 3)],
            records: 3, skipped: 0, fingerprint: "synthetic")
    })
    DispatchQueue.main.async {
      importer.show(parent: parent, local: [.init(output: "MacBook Pro", code: "mbp", weight: "100", spoken: "")], excluded: []) { values in
        label.stringValue = "验收草稿：新增 \(values.count) 条；语音热词均关闭：\(values.allSatisfy { $0.doubaoHotword == false })。未写文件。"
      }
    }
    app.activate(ignoringOtherApps: true); app.run()
  }
}
