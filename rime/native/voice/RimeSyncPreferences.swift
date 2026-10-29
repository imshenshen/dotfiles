import AppKit

@MainActor
final class RimeSyncPreferences: NSObject, NSWindowDelegate {
  static let shared = RimeSyncPreferences()
  private var window: NSWindow?
  private let endpoint = NSTextField()
  private let bucket = NSTextField()
  private let prefix = NSTextField()
  private let accessKeyID = NSTextField()
  private let accessKeySecret = NSSecureTextField()
  private let autoSync = NSButton(checkboxWithTitle: "自动同步（保存词典后、启动时和每 10 分钟）", target: nil, action: nil)
  private let syncUserDB = NSButton(checkboxWithTitle: "同时同步学习词库（Rime sync 快照）", target: nil, action: nil)
  private let message = NSTextField(wrappingLabelWithString: "")
  private let spinner = NSProgressIndicator()
  private let testButton = NSButton()
  private let syncButton = NSButton()
  private let saveButton = NSButton()
  private var testTask: Task<Void, Never>?
  private var statusObserver: NSObjectProtocol?

  func show() {
    if window == nil { create() }
    endpoint.stringValue = RimeSyncSettings.endpoint
    bucket.stringValue = RimeSyncSettings.bucket
    prefix.stringValue = RimeSyncSettings.prefix
    if let saved = RimeSyncCredentials.current() {
      accessKeyID.stringValue = saved.accessKeyID
      accessKeySecret.placeholderString = "已保存；留空保持原值"
    } else {
      accessKeyID.stringValue = ""
      accessKeySecret.placeholderString = "填写 AccessKey Secret"
    }
    accessKeySecret.stringValue = ""
    autoSync.state = RimeSyncSettings.autoSync ? .on : .off
    syncUserDB.state = RimeSyncSettings.syncUserDB ? .on : .off
    message.stringValue = RimeSyncService.shared.status
    updateButtons()
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeFirstResponder(accessKeySecret)
  }

  private func create() {
    let window = VoiceEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 570),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "词库自动同步"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    self.window = window
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 570))
    window.contentView = root

    let intro = NSTextField(wrappingLabelWithString:
      "固定词条、语音别名和热词作为一个加密 bundle 同步；学习词库使用 Rime sync 快照，不直接复制运行中的 userdb。凭证只保存在本机钥匙串。")
    intro.frame = NSRect(x: 24, y: 506, width: 612, height: 42)
    intro.font = .systemFont(ofSize: 11)
    intro.textColor = .secondaryLabelColor
    root.addSubview(intro)

    func label(_ text: String, _ y: CGFloat) {
      let field = NSTextField(labelWithString: text)
      field.frame = NSRect(x: 24, y: y, width: 118, height: 24)
      root.addSubview(field)
    }
    label("Endpoint", 461)
    endpoint.frame = NSRect(x: 150, y: 457, width: 486, height: 28)
    root.addSubview(endpoint)
    label("Bucket", 421)
    bucket.frame = NSRect(x: 150, y: 417, width: 486, height: 28)
    root.addSubview(bucket)
    label("Prefix", 381)
    prefix.frame = NSRect(x: 150, y: 377, width: 486, height: 28)
    root.addSubview(prefix)

    label("AccessKey ID", 332)
    accessKeyID.frame = NSRect(x: 150, y: 328, width: 486, height: 28)
    root.addSubview(accessKeyID)
    label("AccessKey Secret", 292)
    accessKeySecret.frame = NSRect(x: 150, y: 288, width: 486, height: 28)
    root.addSubview(accessKeySecret)

    autoSync.frame = NSRect(x: 150, y: 252, width: 486, height: 24)
    autoSync.font = .systemFont(ofSize: 12)
    root.addSubview(autoSync)
    syncUserDB.frame = NSRect(x: 150, y: 226, width: 486, height: 24)
    syncUserDB.font = .systemFont(ofSize: 12)
    root.addSubview(syncUserDB)

    let explanation = NSTextField(wrappingLabelWithString:
      "加密密钥由 AccessKey Secret 在本机派生；更换 Secret 后远端旧数据无法解密。建议为该 bucket 使用独立的 RAM 子账号，并只授予 shurufa/ 前缀权限。")
    explanation.frame = NSRect(x: 24, y: 174, width: 612, height: 38)
    explanation.font = .systemFont(ofSize: 10)
    explanation.textColor = .tertiaryLabelColor
    root.addSubview(explanation)

    message.frame = NSRect(x: 24, y: 125, width: 612, height: 40)
    message.font = .systemFont(ofSize: 11)
    message.textColor = .secondaryLabelColor
    root.addSubview(message)

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isIndeterminate = true
    spinner.isDisplayedWhenStopped = false
    spinner.frame = NSRect(x: 620, y: 139, width: 18, height: 18)
    root.addSubview(spinner)

    testButton.title = "测试连接"
    testButton.bezelStyle = .rounded
    testButton.target = self
    testButton.action = #selector(testConnection)
    testButton.frame = NSRect(x: 24, y: 82, width: 112, height: 32)
    root.addSubview(testButton)

    syncButton.title = "立即同步"
    syncButton.bezelStyle = .rounded
    syncButton.target = self
    syncButton.action = #selector(syncNow)
    syncButton.frame = NSRect(x: 146, y: 82, width: 112, height: 32)
    root.addSubview(syncButton)

    let clear = NSButton(title: "删除凭证", target: self, action: #selector(clearCredentials))
    clear.bezelStyle = .rounded
    clear.frame = NSRect(x: 268, y: 82, width: 112, height: 32)
    root.addSubview(clear)

    saveButton.title = "保存"
    saveButton.bezelStyle = .rounded
    saveButton.target = self
    saveButton.action = #selector(save)
    saveButton.frame = NSRect(x: 500, y: 82, width: 136, height: 32)
    saveButton.keyEquivalent = "\r"
    root.addSubview(saveButton)

    statusObserver = NotificationCenter.default.addObserver(
      forName: RimeSyncService.statusChanged, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.message.stringValue = RimeSyncService.shared.status }
    }
  }

  private func updateButtons() {
    let busy = RimeSyncService.shared.syncing
    for button in [testButton, syncButton, saveButton] { button.isEnabled = !busy }
  }

  private func configuration(requireCredentials: Bool = true) -> OSSConfiguration? {
    let enteredID = accessKeyID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let enteredSecret = accessKeySecret.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let saved = RimeSyncCredentials.current()
    let id = enteredID.isEmpty ? (saved?.accessKeyID ?? "") : enteredID
    let secret = enteredSecret.isEmpty ? (saved?.accessKeySecret ?? "") : enteredSecret
    if requireCredentials && (id.isEmpty || secret.isEmpty) {
      message.stringValue = "请填写 AccessKey ID 和 Secret。"
      return nil
    }
    do {
      return try OSSConfiguration(endpoint: endpoint.stringValue, bucket: bucket.stringValue,
                                  prefix: prefix.stringValue, accessKeyID: id,
                                  accessKeySecret: secret)
    } catch {
      message.stringValue = error.localizedDescription
      return nil
    }
  }

  @discardableResult
  private func persist(showSuccess: Bool) -> Bool {
    guard let config = configuration() else { return false }
    do {
      let enteredID = accessKeyID.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      let enteredSecret = accessKeySecret.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
      if !enteredID.isEmpty { try RimeSyncCredentials.save(enteredID, account: "accessKeyID") }
      if !enteredSecret.isEmpty { try RimeSyncCredentials.save(enteredSecret, account: "accessKeySecret") }
      RimeSyncSettings.endpoint = config.endpoint.absoluteString
      RimeSyncSettings.bucket = config.bucket
      RimeSyncSettings.prefix = config.prefix
      RimeSyncSettings.autoSync = autoSync.state == .on
      RimeSyncSettings.syncUserDB = syncUserDB.state == .on
      accessKeyID.stringValue = config.accessKeyID
      accessKeySecret.stringValue = ""
      accessKeySecret.placeholderString = "已保存；留空保持原值"
      if showSuccess { message.stringValue = "已保存。可点击“立即同步”或等待自动同步。" }
      RimeSyncService.shared.schedule(after: 1)
      return true
    } catch {
      message.stringValue = error.localizedDescription
      return false
    }
  }

  @objc private func save() { _ = persist(showSuccess: true) }

  @objc private func testConnection() {
    guard let config = configuration() else { return }
    testTask?.cancel()
    testButton.isEnabled = false
    spinner.startAnimation(nil)
    message.stringValue = "正在测试 OSS 连接…"
    testTask = Task { @MainActor [weak self] in
      defer {
        self?.spinner.stopAnimation(nil)
        self?.testButton.isEnabled = true
      }
      do {
        let client = OSSSyncClient(configuration: config)
        try await client.testConnection()
        guard !Task.isCancelled else { return }
        self?.message.stringValue = "连接成功；读写 shurufa/ 前缀正常。点击“保存”后才会启用自动同步。"
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        self?.message.stringValue = error.localizedDescription
      }
    }
  }

  @objc private func syncNow() {
    guard persist(showSuccess: false) else { return }
    spinner.startAnimation(nil)
    updateButtons()
    RimeSyncService.shared.syncNow { [weak self] result in
      guard let self else { return }
      self.spinner.stopAnimation(nil)
      self.updateButtons()
      switch result {
      case .success(let outcome):
        self.message.stringValue = outcome.userDBError ??
          "已同步 · \(outcome.records) 条词典 · \(outcome.userDBFiles) 个学习快照"
      case .failure(let error):
        self.message.stringValue = error.localizedDescription
      }
    }
  }

  @objc private func clearCredentials() {
    do {
      try RimeSyncCredentials.remove("accessKeyID")
      try RimeSyncCredentials.remove("accessKeySecret")
      accessKeyID.stringValue = ""
      accessKeySecret.stringValue = ""
      accessKeySecret.placeholderString = "填写 AccessKey Secret"
      message.stringValue = "已删除本机 OSS 凭证；自动同步不会运行。"
    } catch { message.stringValue = error.localizedDescription }
  }

  func windowWillClose(_ notification: Notification) {
    testTask?.cancel(); testTask = nil
    spinner.stopAnimation(nil)
    accessKeySecret.stringValue = ""
  }
}


@MainActor
public enum RimeSyncUI {
  private static var settingsObserver: NSObjectProtocol?
  public static func startServices(rimeSync: @escaping () -> Bool) {
    RimeSyncService.shared.start(rimeSync: rimeSync)
    guard settingsObserver == nil else { return }
    settingsObserver = DistributedNotificationCenter.default().addObserver(
      forName: .init("SquirrelRimeSyncSettingsNotification"), object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { RimeSyncPreferences.shared.show() }
    }
  }
  public static func openSettings() {
    RimeSyncPreferences.shared.show()
  }
  public static func dictionaryDidChange() {
    RimeSyncService.shared.schedule(after: 3)
  }
  public static func scheduleNow() {
    RimeSyncService.shared.schedule(after: 0)
  }
  public static func setDictionaryEditing(_ value: Bool) {
    RimeSyncService.shared.setDictionaryEditing(value)
  }
}
