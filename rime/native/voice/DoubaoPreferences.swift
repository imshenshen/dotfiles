import AppKit

@MainActor final class DoubaoPreferences: NSObject, NSWindowDelegate {
  static let shared = DoubaoPreferences()
  private var window: NSWindow?
  private let model = NSPopUpButton()
  private let auth = NSPopUpButton()
  private let key = NSSecureTextField()
  private let appID = NSTextField()
  private let token = NSSecureTextField()
  private let message = NSTextField(labelWithString: "")
  private let appLabel = NSTextField(labelWithString: "App ID")
  private let tokenLabel = NSTextField(labelWithString: "Access Token")
  private let resources = ["volc.seedasr.sauc.duration", "volc.seedasr.sauc.concurrent",
                           "volc.bigasr.sauc.duration", "volc.bigasr.sauc.concurrent"]
  func show() {
    if window == nil { create() }
    model.selectItem(at: resources.firstIndex(of: VoiceSettings.doubaoResource) ?? 0)
    auth.selectItem(at: VoiceSettings.defaults.string(forKey: "doubaoAuthMode") == "legacy" ? 1 : 0)
    key.stringValue = ""; token.stringValue = ""; appID.stringValue = VoiceSettings.doubaoAppID
    key.placeholderString = VoiceCredentials.read("apiKey") == nil ? "填写语音 API Key" : "已保存；留空保持原值"
    token.placeholderString = VoiceCredentials.read("accessToken") == nil ? "填写语音 Access Token" : "已保存；留空保持原值"
    message.stringValue = "登录控制台不能代替接口凭证；需开通对应流式识别服务。"
    updateAuth(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    window?.makeFirstResponder(auth.indexOfSelectedItem == 1 ? appID : key)
  }
  private func create() {
    let window = VoiceEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 624),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "豆包语音配置"; window.isReleasedWhenClosed = false; window.delegate = self
    window.center(); self.window = window
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 624)); window.contentView = root
    root.addSubview(VoiceSetupGuide(service: .speech, frame: NSRect(x: 24, y: 380, width: 492, height: 220)))
    func label(_ title: String, _ y: CGFloat) {
      let label = NSTextField(labelWithString: title); label.frame = NSRect(x: 24, y: y, width: 136, height: 26)
      root.addSubview(label)
    }
    label("识别模型", 326)
    model.frame = NSRect(x: 168, y: 323, width: 344, height: 32)
    model.addItems(withTitles: ["2.0 · 按时长（推荐）", "2.0 · 按并发", "1.0 · 按时长（兼容）", "1.0 · 按并发（兼容）"])
    root.addSubview(model)
    label("接口凭证", 284)
    auth.frame = NSRect(x: 168, y: 281, width: 344, height: 32)
    auth.addItems(withTitles: ["新版 API Key", "旧版 App ID + Access Token"])
    auth.target = self; auth.action = #selector(updateAuth); root.addSubview(auth)
    label("API Key", 238)
    key.frame = NSRect(x: 168, y: 236, width: 344, height: 28); root.addSubview(key)
    appLabel.frame = NSRect(x: 24, y: 193, width: 136, height: 26); root.addSubview(appLabel)
    appID.frame = NSRect(x: 168, y: 190, width: 344, height: 28); root.addSubview(appID)
    tokenLabel.frame = NSRect(x: 24, y: 148, width: 136, height: 26); root.addSubview(tokenLabel)
    token.frame = NSRect(x: 168, y: 145, width: 344, height: 28); root.addSubview(token)
    message.frame = NSRect(x: 24, y: 95, width: 492, height: 38)
    message.font = .systemFont(ofSize: 11); message.textColor = .secondaryLabelColor
    message.lineBreakMode = .byWordWrapping; message.maximumNumberOfLines = 2; root.addSubview(message)
    let disclosure = NSTextField(labelWithString: "启用豆包后，录音会发送至火山引擎；密钥保存在本机钥匙串。")
    disclosure.frame = NSRect(x: 24, y: 60, width: 492, height: 24); disclosure.font = .systemFont(ofSize: 11)
    disclosure.textColor = .secondaryLabelColor; root.addSubview(disclosure)
    let clear = NSButton(title: "删除凭证", target: self, action: #selector(clearCredentials))
    clear.frame = NSRect(x: 24, y: 19, width: 110, height: 32); clear.bezelStyle = .rounded; root.addSubview(clear)
    let save = NSButton(title: "保存", target: self, action: #selector(save))
    save.frame = NSRect(x: 405, y: 19, width: 110, height: 32); save.bezelStyle = .rounded; root.addSubview(save)
  }
  @objc private func updateAuth() {
    let legacy = auth.indexOfSelectedItem == 1
    key.isEnabled = !legacy; appID.isEnabled = legacy; token.isEnabled = legacy
    appLabel.textColor = legacy ? .labelColor : .tertiaryLabelColor
    tokenLabel.textColor = legacy ? .labelColor : .tertiaryLabelColor
  }
  @objc private func save() {
    let legacy = auth.indexOfSelectedItem == 1
    let enteredKey = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let enteredToken = token.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let id = appID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if legacy {
      guard !id.isEmpty, !enteredToken.isEmpty || VoiceCredentials.read("accessToken") != nil else {
        message.stringValue = "请填写 App ID 和 Access Token。"; return
      }
    } else if enteredKey.isEmpty && VoiceCredentials.read("apiKey") == nil {
      message.stringValue = "请填写语音 API Key。"; return
    }
    do {
      if !enteredKey.isEmpty { try VoiceCredentials.save(enteredKey, account: "apiKey") }
      if !enteredToken.isEmpty { try VoiceCredentials.save(enteredToken, account: "accessToken") }
      VoiceSettings.doubaoAppID = id
      VoiceSettings.doubaoResource = resources[model.indexOfSelectedItem]
      VoiceSettings.defaults.set(legacy ? "legacy" : "apiKey", forKey: "doubaoAuthMode")
      key.stringValue = ""; token.stringValue = ""; message.stringValue = "已保存到本机钥匙串。"; window?.close()
    } catch { message.stringValue = error.localizedDescription }
  }
  @objc private func clearCredentials() {
    VoiceCredentials.clear(); key.stringValue = ""; token.stringValue = ""; message.stringValue = "已删除本机语音接口凭证。"
  }
  func windowWillClose(_ notification: Notification) { key.stringValue = ""; token.stringValue = "" }
}
