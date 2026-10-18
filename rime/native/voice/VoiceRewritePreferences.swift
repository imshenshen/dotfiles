import AppKit

@MainActor final class VoiceRewritePreferences: NSObject, NSWindowDelegate {
  static let shared = VoiceRewritePreferences()
  private var window: NSWindow?
  private let model = NSTextField()
  private let key = NSSecureTextField()
  private let message = NSTextField(wrappingLabelWithString: "")
  func show() {
    if window == nil { create() }
    model.stringValue = VoiceSettings.rewriteModel; key.stringValue = ""
    key.placeholderString = VoiceCredentials.read("rewriteAPIKey") == nil ? "填写方舟 API Key" : "已保存；留空保持原值"
    message.stringValue = "只在点击重写时发送本轮识别文本，不读取其他应用全文或发送整份词典。"
    window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  private func create() {
    let window = VoiceEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 540),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "文字重写配置"; window.isReleasedWhenClosed = false; window.delegate = self
    window.center(); self.window = window
    guard let root = window.contentView else { return }
    root.addSubview(VoiceSetupGuide(service: .rewrite, frame: NSRect(x: 24, y: 296, width: 492, height: 220)))
    for (title, y) in [("方舟 API Key", CGFloat(228)), ("模型 ID", CGFloat(182))] {
      let label = NSTextField(labelWithString: title); label.frame = NSRect(x: 24, y: y, width: 120, height: 26); root.addSubview(label)
    }
    key.frame = NSRect(x: 150, y: 228, width: 366, height: 26); root.addSubview(key)
    model.frame = NSRect(x: 150, y: 182, width: 366, height: 26)
    model.placeholderString = "例如 doubao-seed-2-1-lite-260915"; root.addSubview(model)
    let hint = NSTextField(wrappingLabelWithString: "豆包方舟 · 北京地域 · 独立于语音接口\n带思考标签也可用，程序会关闭思考；密钥保存在本机钥匙串。")
    hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor
    hint.frame = NSRect(x: 24, y: 122, width: 492, height: 44); root.addSubview(hint)
    message.frame = NSRect(x: 24, y: 65, width: 492, height: 44)
    message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor; root.addSubview(message)
    let remove = NSButton(title: "删除重写密钥", target: self, action: #selector(clear))
    remove.frame = NSRect(x: 24, y: 18, width: 140, height: 32); remove.bezelStyle = .rounded; root.addSubview(remove)
    let save = NSButton(title: "保存", target: self, action: #selector(save))
    save.frame = NSRect(x: 406, y: 18, width: 110, height: 32); save.bezelStyle = .rounded; root.addSubview(save)
  }
  @objc private func save() {
    let entered = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty, !entered.isEmpty || VoiceCredentials.read("rewriteAPIKey") != nil else {
      message.stringValue = "请填写模型 ID 和方舟 API Key。"; return
    }
    do {
      if !entered.isEmpty { try VoiceCredentials.save(entered, account: "rewriteAPIKey") }
      VoiceSettings.rewriteModel = id; key.stringValue = ""; window?.close()
    } catch { message.stringValue = error.localizedDescription }
  }
  @objc private func clear() {
    do { try VoiceCredentials.remove("rewriteAPIKey"); key.stringValue = ""; message.stringValue = "已删除重写密钥，语音凭证未变。" }
    catch { message.stringValue = error.localizedDescription }
  }
  func windowWillClose(_ notification: Notification) { key.stringValue = "" }
}
