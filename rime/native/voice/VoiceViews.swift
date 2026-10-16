import AppKit
import AVFoundation

@MainActor final class VoiceWaveform: NSView {
  private var values = [CGFloat](repeating: 0, count: 24)
  private var targets = [CGFloat](repeating: 0, count: 24)
  private var timer: Timer?
  var tint = NSColor.controlAccentColor
  override init(frame: NSRect) {
    super.init(frame: frame)
    setAccessibilityElement(true); setAccessibilityRole(.image)
    setAccessibilityLabel("麦克风实时音频波形")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:)") }
  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self else { return }
        for i in self.values.indices { self.values[i] += (self.targets[i] - self.values[i]) * 0.28 }
        self.needsDisplay = true
      }
    }
  }
  func push(_ level: Double) {
    targets.removeFirst(); targets.append(CGFloat(min(1, max(0, sqrt(level) * 5.5))))
    setAccessibilityValue("输入音量 \(Int(min(1, level * 4) * 100))%")
    start()
  }
  func stop() {
    timer?.invalidate(); timer = nil
    values = values.map { _ in 0 }; targets = values; needsDisplay = true
  }
  override func draw(_ dirtyRect: NSRect) {
    tint.setFill()
    let step = bounds.width / CGFloat(values.count)
    for i in values.indices {
      let height = max(3, values[i] * (bounds.height - 4))
      let rect = NSRect(x: CGFloat(i) * step + 1, y: (bounds.height - height) / 2,
                        width: max(2, step - 2), height: height)
      NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
    }
  }
}

@MainActor final class VoiceHUDPanel: NSPanel {
  var editingResult = false
  override var canBecomeKey: Bool { editingResult }
}

@MainActor final class VoiceHUD: NSObject, NSTextViewDelegate {
  let panel: VoiceHUDPanel
  private let root = NSView()
  private let footer = NSView()
  private let scroll = NSScrollView()
  private let textView = VoiceCopyTextView()
  private let label = NSTextField(labelWithString: "")
  private let wave = VoiceWaveform(frame: .zero)
  private let cancelButton = NSButton()
  private let finishButton = NSButton()
  private var recording = false
  private var resultReady = false
  var hasPendingResult: Bool { resultReady && panel.isVisible }
  var onStop: (() -> Void)?
  var onCancel: (() -> Void)?
  override init() {
    panel = VoiceHUDPanel(contentRect: NSRect(x: 0, y: 0, width: 180, height: 56),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    super.init()
    panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
    panel.hasShadow = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.becomesKeyOnlyIfNeeded = true
    root.wantsLayer = true; root.layer?.cornerRadius = 18; root.layer?.masksToBounds = true
    root.layer?.backgroundColor = NSColor.black.cgColor
    root.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor; root.layer?.borderWidth = 1
    panel.contentView = root; root.addSubview(footer)
    wave.tint = .white; footer.addSubview(wave)
    for button in [cancelButton, finishButton] {
      button.isBordered = false; button.wantsLayer = true; button.layer?.cornerRadius = 15
      button.target = self; footer.addSubview(button)
    }
    cancelButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
    cancelButton.contentTintColor = .white; cancelButton.action = #selector(cancel)
    cancelButton.image = symbol("xmark", "取消听写或关闭结果")
    finishButton.layer?.backgroundColor = NSColor.white.cgColor; finishButton.contentTintColor = .black
    finishButton.action = #selector(finish)
    label.font = .systemFont(ofSize: 9); label.textColor = NSColor.white.withAlphaComponent(0.65)
    label.alignment = .center; label.lineBreakMode = .byTruncatingMiddle; root.addSubview(label)
    scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder
    textView.isRichText = false; textView.drawsBackground = false; textView.textColor = .white
    textView.insertionPointColor = .white; textView.font = .systemFont(ofSize: 13)
    textView.textContainerInset = NSSize(width: 4, height: 4)
    textView.isVerticallyResizable = true; textView.isHorizontallyResizable = false
    textView.autoresizingMask = [.width]; textView.textContainer?.widthTracksTextView = true
    textView.delegate = self; textView.setAccessibilityLabel("语音内容")
    textView.resultAvailable = { [weak self] in self?.hasPendingResult == true }
    textView.copied = { [weak self] in self?.dismissResult() }
    scroll.documentView = textView; root.addSubview(scroll); layout()
  }
  private func symbol(_ name: String, _ description: String) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: description)?
      .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
  }
  private func layout() {
    let expanded = !textView.string.isEmpty || resultReady
    let width: CGFloat = expanded ? 360 : 180
    let measured = (textView.string as NSString).boundingRect(with: NSSize(width: width-32, height: 10000),
      options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 13)]).height
    let body = expanded ? min(200, max(resultReady ? 70 : 28, ceil(measured)+12)) : 0
    let height = expanded ? 68+body : 56
    let old = panel.frame
    let screen = NSScreen.screens.first(where: { $0.frame.intersects(old) }) ?? NSScreen.main
    let frame = screen?.visibleFrame ?? old
    panel.setFrame(NSRect(x: frame.midX-width/2, y: frame.minY+18, width: width, height: height), display: true)
    root.frame = NSRect(x: 0, y: 0, width: width, height: height)
    footer.frame = NSRect(x: (width-180)/2, y: 3, width: 180, height: 36)
    cancelButton.frame = NSRect(x: 3, y: 3, width: 30, height: 30)
    finishButton.frame = NSRect(x: 147, y: 3, width: 30, height: 30)
    wave.frame = NSRect(x: 45, y: 7, width: 90, height: 22)
    label.frame = NSRect(x: 8, y: 41, width: width-16, height: 12)
    scroll.isHidden = !expanded
    scroll.frame = NSRect(x: 12, y: 62, width: width-24, height: body)
    textView.setFrameSize(NSSize(width: width-24, height: max(body, measured+12)))
  }
  func show(_ text: String, recording: Bool) {
    label.stringValue = text
    if resultReady && !recording { panel.orderFrontRegardless(); return }
    self.recording = recording; panel.editingResult = false; textView.isEditable = false
    cancelButton.isHidden = !recording; finishButton.isHidden = !recording; wave.isHidden = false
    finishButton.image = symbol("checkmark", "完成听写")
    if recording { wave.start() } else { wave.stop(); textView.string = "" }
    layout(); panel.orderFrontRegardless()
  }
  func preview(_ text: String) {
    guard !resultReady else { return }
    textView.string = text; textView.isEditable = false; layout()
    textView.scrollRangeToVisible(NSRange(location: text.utf16.count, length: 0))
    panel.orderFrontRegardless()
  }
  func showResult(_ text: String) {
    resultReady = true; recording = false; panel.editingResult = true; wave.stop(); wave.isHidden = true
    textView.string = text; textView.isEditable = true; textView.isSelectable = true
    label.stringValue = "可编辑 · ⌘C 或右侧复制后关闭"
    cancelButton.isHidden = false; finishButton.isHidden = false
    finishButton.image = symbol("doc.on.doc", "复制文字"); finishButton.toolTip = "复制文字"
    layout(); panel.makeKeyAndOrderFront(nil)
  }
  func textDidChange(_ notification: Notification) { if resultReady { layout() } }
  func audio(_ level: Double) { wave.push(level) }
  func containsInteraction(at point: CGPoint) -> Bool {
    guard let primary = NSScreen.screens.first else { return false }
    return panel.isVisible && panel.frame.contains(NSPoint(x: point.x, y: primary.frame.maxY-point.y))
  }
  func hide() { wave.stop(); panel.orderOut(nil) }
  private func dismissResult() {
    resultReady = false; textView.string = ""; panel.editingResult = false; hide()
  }
  @objc private func cancel() {
    if resultReady { dismissResult() }
    else { onCancel?() }
  }
  @objc private func finish() {
    if resultReady {
      textView.copyAll()
    } else if recording { onStop?() }
  }
}

public enum RimeVoiceUI {
  @MainActor public static func openSettings() { VoicePreferences.shared.show() }
  @MainActor public static func startServices() { VoiceSession.shared.startServices() }
  // Disabled normally. The CLI may only exercise the known public audio fixture.
  @MainActor public static func acceptance(_ action: String) {
    guard VoiceSettings.acceptanceFixture != nil, VoiceSettings.provider == "apple" else { return }
    VoiceSession.shared.acceptance(action)
  }
}

@MainActor final class VoicePreferences: NSObject, NSWindowDelegate {
  static let shared = VoicePreferences()
  private var window: NSWindow?
  private let providerMenu = NSPopUpButton()
  private let providerDescription = NSTextField(labelWithString: "")
  private let configureCloud = NSButton(title: "配置豆包…", target: nil, action: nil)
  private var previousApp: NSRunningApplication?
  private let deviceMenu = NSPopUpButton()
  private let descriptionLabel = NSTextField(labelWithString: "")
  private let testLabel = NSTextField(labelWithString: "点击测试，再对麦克风说话")
  private let wave = VoiceWaveform(frame: NSRect(x: 0, y: 0, width: 440, height: 38))
  private let testButton = NSButton(title: "测试麦克风", target: nil, action: nil)
  private let spacing = NSButton(checkboxWithTitle: "中文与英文、数字之间自动加空格", target: nil, action: nil)
  private let pauseMenu = NSPopUpButton()
  private let shortcutRecorder = VoiceShortcutRecorder()
  private let shortcutPermission = NSTextField(labelWithString: "")
  private let fieldPermission = NSTextField(labelWithString: "")
  private let shortcutPermissionButton = NSButton(title: "授权", target: nil, action: nil)
  private let fieldPermissionButton = NSButton(title: "授权", target: nil, action: nil)
  private var permissionTimer: Timer?
  private var child: Process?
  private var commands: FileHandle?
  private var testSession = ""
  private var testing = false
  private var devices: [VoiceDevice] = []
  func show() {
    if window == nil { createWindow() }
    if let foreground = NSWorkspace.shared.frontmostApplication,
       foreground.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = foreground }
    refreshDevices()
    spacing.state = VoiceSettings.mixedSpacing ? .on : .off
    pauseMenu.selectItem(at: [800, 1600, 2500, 4000].firstIndex(of: VoiceSettings.pauseMilliseconds) ?? 1)
    refreshProvider()
    refreshPermissions()
    permissionTimer?.invalidate()
    permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.refreshPermissions() }
    }
    window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  private func createWindow() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 724),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "语音设置"; window.isReleasedWhenClosed = false; window.delegate = self
    window.center(); self.window = window
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 724)); window.contentView = root
    func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ size: CGFloat = 13, _ bold: Bool = false) {
      let field = NSTextField(labelWithString: text)
      field.frame = NSRect(x: x, y: y, width: width, height: size > 20 ? 32 : 24)
      field.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
      if !bold { field.textColor = .secondaryLabelColor }
      root.addSubview(field)
    }
    label("语音输入", 32, 662, 210, 26, true)
    providerMenu.frame = NSRect(x: 250, y: 656, width: 258, height: 34)
    providerMenu.addItems(withTitles: ["Apple 本地识别", "豆包云识别（二遍）"])
    providerMenu.target = self; providerMenu.action = #selector(providerChanged); root.addSubview(providerMenu)
    providerDescription.frame = NSRect(x: 32, y: 628, width: 365, height: 24)
    providerDescription.font = .systemFont(ofSize: 12); providerDescription.textColor = .secondaryLabelColor
    root.addSubview(providerDescription)
    configureCloud.frame = NSRect(x: 401, y: 625, width: 108, height: 30)
    configureCloud.bezelStyle = .rounded; configureCloud.target = self; configureCloud.action = #selector(openCloud)
    root.addSubview(configureCloud)
    label("麦克风", 32, 586, 360, 14, true)
    deviceMenu.frame = NSRect(x: 30, y: 546, width: 440, height: 32)
    deviceMenu.target = self; deviceMenu.action = #selector(deviceChanged); root.addSubview(deviceMenu)
    let refresh = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "刷新输入设备")!, target: self, action: #selector(refreshAction))
    refresh.frame = NSRect(x: 476, y: 547, width: 30, height: 30); refresh.isBordered = false; root.addSubview(refresh)
    descriptionLabel.frame = NSRect(x: 32, y: 513, width: 472, height: 22)
    descriptionLabel.font = .systemFont(ofSize: 11); descriptionLabel.textColor = .secondaryLabelColor
    root.addSubview(descriptionLabel)
    let card = NSView(frame: NSRect(x: 32, y: 387, width: 476, height: 118))
    card.wantsLayer = true; card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    card.layer?.cornerRadius = 14; root.addSubview(card)
    wave.frame = NSRect(x: 18, y: 64, width: 440, height: 36); card.addSubview(wave)
    testLabel.frame = NSRect(x: 18, y: 22, width: 280, height: 22)
    testLabel.font = .systemFont(ofSize: 12); testLabel.textColor = .secondaryLabelColor; card.addSubview(testLabel)
    testButton.frame = NSRect(x: 315, y: 18, width: 142, height: 32)
    testButton.bezelStyle = .rounded; testButton.target = self; testButton.action = #selector(testMicrophone)
    card.addSubview(testButton)
    spacing.frame = NSRect(x: 32, y: 349, width: 345, height: 24)
    spacing.target = self; spacing.action = #selector(spacingChanged); root.addSubview(spacing)
    let dictionary = NSButton(title: "用户词典…", target: self, action: #selector(openDictionary))
    dictionary.bezelStyle = .rounded; dictionary.frame = NSRect(x: 389, y: 344, width: 119, height: 32); root.addSubview(dictionary)
    label("语音、五笔和拼音共用；自定义词条内部格式优先。", 32, 319, 472, 11)
    label("豆包停顿容忍", 32, 280, 170, 13)
    pauseMenu.frame = NSRect(x: 220, y: 277, width: 288, height: 32)
    pauseMenu.addItems(withTitles: ["0.8 秒 · 快速确认", "1.6 秒 · 推荐", "2.5 秒 · 留出思考时间", "4 秒 · 长停顿"])
    pauseMenu.target = self; pauseMenu.action = #selector(pauseChanged); root.addSubview(pauseMenu)
    label("语音快捷键", 32, 222, 180, 14, true)
    shortcutRecorder.button.frame = NSRect(x: 220, y: 216, width: 288, height: 34)
    root.addSubview(shortcutRecorder.button)
    label("点击后轻按左/右修饰键或组合键；再按一次完成。", 32, 181, 472, 11)
    for (field, button, y) in [(shortcutPermission, shortcutPermissionButton, CGFloat(140)),
                               (fieldPermission, fieldPermissionButton, CGFloat(101))] {
      field.frame = NSRect(x: 32, y: y, width: 346, height: 24)
      field.font = .systemFont(ofSize: 12); field.textColor = .secondaryLabelColor; root.addSubview(field)
      button.frame = NSRect(x: 390, y: y - 3, width: 116, height: 30)
      button.bezelStyle = .rounded; button.target = self; root.addSubview(button)
    }
    shortcutPermissionButton.action = #selector(authorizeShortcut)
    fieldPermissionButton.action = #selector(authorizeFields)
    let start = NSButton(title: "开始听写", target: self, action: #selector(startDictation))
    start.bezelStyle = .rounded; start.frame = NSRect(x: 391, y: 57, width: 117, height: 32)
    root.addSubview(start)
    label("切换应用仍会录音，结束后处理未写入的文字。", 32, 29, 472, 11)
  }
  private func refreshProvider() {
    let cloud = VoiceSettings.provider == "doubao"
    providerMenu.selectItem(at: cloud ? 1 : 0); configureCloud.isHidden = !cloud
    pauseMenu.isEnabled = cloud
    providerDescription.stringValue = cloud ? "音频发送至火山引擎 · 实时与二遍识别" : "Apple 本地识别 · 音频不上传"
  }
  @objc private func providerChanged() {
    stopTest(); VoiceSettings.provider = providerMenu.indexOfSelectedItem == 1 ? "doubao" : "apple"; refreshProvider()
  }
  @objc private func spacingChanged() { VoiceSettings.mixedSpacing = spacing.state == .on }
  @objc private func pauseChanged() { VoiceSettings.pauseMilliseconds = [800, 1600, 2500, 4000][pauseMenu.indexOfSelectedItem] }
  @objc private func openDictionary() { VoiceDictionaryPreferences.shared.show() }
  @objc private func openCloud() { DoubaoPreferences.shared.show() }
  @objc private func startDictation() {
    stopTest(); window?.close()
    previousApp?.activate(options: [.activateIgnoringOtherApps])
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 700_000_000); VoiceSession.shared.toggle()
    }
  }
  @objc private func authorizeShortcut() { VoiceGlobalShortcut.shared.requestPermission(); refreshPermissions() }
  @objc private func authorizeFields() { VoiceAccessibilityHost.requestPermission(); refreshPermissions() }
  private func refreshPermissions() {
    VoiceGlobalShortcut.shared.start()
    let hotkey = VoiceGlobalShortcut.shared.installed
    shortcutPermission.stringValue = hotkey ? "全局快捷键已启用" :
      (VoiceGlobalShortcut.shared.authorized ? "已授权，快捷键监听未启动；请重启输入法" : "全局快捷键需要辅助功能权限")
    shortcutPermissionButton.isEnabled = !hotkey
    shortcutPermissionButton.title = hotkey ? "已启用" : "打开系统设置"
    let fields = VoiceAccessibilityHost.authorized
    fieldPermission.stringValue = fields ? "可访问其他应用的输入框" : "写入其他应用需要辅助功能权限"
    fieldPermissionButton.isEnabled = !fields
    fieldPermissionButton.title = fields ? "已允许" : "打开系统设置"
  }
  @objc private func refreshAction() { stopTest(); refreshDevices() }
  private func refreshDevices() {
    devices = VoiceDevices.inputs()
    let selected = VoiceSettings.deviceUID
    let defaultName = VoiceDevices.selected(uid: "")?.name ?? "暂无可用麦克风"
    deviceMenu.removeAllItems(); deviceMenu.addItem(withTitle: "跟随系统默认（\(defaultName)）")
    deviceMenu.lastItem?.representedObject = ""
    for device in devices {
      deviceMenu.addItem(withTitle: device.name); deviceMenu.lastItem?.representedObject = device.uid
    }
    if !selected.isEmpty, !devices.contains(where: { $0.uid == selected }) {
      deviceMenu.addItem(withTitle: "所选设备已断开"); deviceMenu.lastItem?.representedObject = selected
    }
    if let index = deviceMenu.itemArray.firstIndex(where: { $0.representedObject as? String == selected }) { deviceMenu.selectItem(at: index) }
    updateDeviceDescription()
  }
  private func updateDeviceDescription() {
    let device = VoiceDevices.selected(uid: VoiceSettings.deviceUID)
    descriptionLabel.stringValue = device == nil ? "麦克风不可用，请连接设备或选择其他麦克风。" : "说话时观察波形，没有变化请尝试其他麦克风。"
  }
  @objc private func deviceChanged() {
    stopTest(); VoiceSettings.deviceUID = deviceMenu.selectedItem?.representedObject as? String ?? ""
    updateDeviceDescription()
  }
  @objc private func testMicrophone() {
    if testing { stopTest(); return }
    if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
      Task { [weak self] in
        let allowed = await AVCaptureDevice.requestAccess(for: .audio)
        self?.testLabel.stringValue = allowed ? "已授权，再点击测试麦克风" : "请在系统设置中允许麦克风"
      }
      return
    }
    guard VoiceDevices.selected(uid: VoiceSettings.deviceUID) != nil else { testLabel.stringValue = "所选麦克风已断开"; return }
    testSession = UUID().uuidString; let token = testSession
    let child = Process(), input = Pipe(), output = Pipe()
    child.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/RimeVoice.app/Contents/MacOS/RimeVoice")
    child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
    child.terminationHandler = { [weak self] process in
      let code = process.terminationStatus
      Task { @MainActor in
        guard let self, self.testSession == token, self.testing else { return }
        self.stopTest()
        self.testLabel.stringValue = "麦克风测试程序已退出（\(code)），请检查系统权限。"
      }
    }
    do { try child.run() } catch { testLabel.stringValue = "无法启动麦克风测试"; return }
    self.child = child; commands = input.fileHandleForWriting; testing = true
    testButton.title = "停止测试"; testLabel.stringValue = "请说话，观察波形"; wave.start()
    let command = ["action": "meter", "session": token, "device": VoiceSettings.deviceUID, "channel": "0"]
    let data = try! JSONSerialization.data(withJSONObject: command)
    try? commands?.write(contentsOf: data + Data([10]))
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      var pending = Data()
      while true {
        let data = output.fileHandleForReading.availableData
        if data.isEmpty { break }; pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
          let line = pending.prefix(upTo: newline); pending.removeSubrange(...newline)
          guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
          DispatchQueue.main.async { self?.testEvent(event, token: token) }
        }
      }
    }
  }
  private func testEvent(_ event: [String: Any], token: String) {
    guard testing, testSession == token, event["session"] as? String == token else { return }
    if event["type"] as? String == "audio", let level = event["level"] as? Double {
      wave.push(level); testLabel.stringValue = level < 0.0001 ? "暂无声音，请检查麦克风" : "已收到声音"
    } else if event["type"] as? String == "error" {
      stopTest(); testLabel.stringValue = event["message"] as? String ?? "麦克风无法使用"
    } else if event["type"] as? String == "connecting" {
      testLabel.stringValue = "正在连接蓝牙麦克风…"
    }
  }
  private func stopTest() {
    testing = false; testSession = ""; wave.stop(); testButton.title = "测试麦克风"
    try? commands?.close(); commands = nil
    let child = self.child; self.child = nil
    if child?.isRunning == true { child?.terminate() }
    testLabel.stringValue = "点击测试，再对麦克风说话"
  }
  func stopPreview() { stopTest() }
  func windowWillClose(_ notification: Notification) {
    stopTest(); shortcutRecorder.finish(nil); permissionTimer?.invalidate(); permissionTimer = nil
  }
  func windowDidResignKey(_ notification: Notification) { if testing { stopTest() }; shortcutRecorder.finish(nil) }
  func windowWillMiniaturize(_ notification: Notification) { stopTest() }
}
