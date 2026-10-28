import AppKit
import InputMethodKit
import Carbon
import OSLog
import AVFoundation

@MainActor private final class InputHost: VoiceTextHost {
  var reportsMarkedSelection: Bool { true }
  var ownsNativeComposition: Bool { true }
  var usesTerminalCellCoordinates: Bool { client?.bundleIdentifier() == "com.googlecode.iterm2" }
  weak var client: IMKTextInput?
  init(_ client: IMKTextInput) { self.client = client }
  var selection: NSRange { client?.selectedRange() ?? NSRange(location: NSNotFound, length: 0) }
  var marked: NSRange { client?.markedRange() ?? NSRange(location: NSNotFound, length: 0) }
  func text(in range: NSRange) -> String? {
    guard range.location != NSNotFound else { return nil }
    if range.length == 0 { return "" }
    return client?.attributedSubstring(from: range)?.string
  }
  func mark(_ text: String, replacing range: NSRange) {
    client?.setMarkedText(text, selectionRange: NSRange(location: text.utf16.count, length: 0), replacementRange: VoiceHostRange.replacement(range, selection: selection, marked: marked))
  }
  func insert(_ text: String, replacing range: NSRange) { client?.insertText(text, replacementRange: VoiceHostRange.replacement(range, selection: selection, marked: marked)) }
}

// Recording belongs to the application, independently of input controllers.
@MainActor public final class RimeVoiceController: NSObject {
  fileprivate let id = UUID()
  fileprivate let clientProvider: () -> IMKTextInput?
  fileprivate let composing: () -> Bool
  fileprivate let hideCandidates: () -> Void
  public init(client: @escaping () -> IMKTextInput?, composing: @escaping () -> Bool,
              hideCandidates: @escaping () -> Void) {
    clientProvider = client; self.composing = composing; self.hideCandidates = hideCandidates
    super.init()
  }
  public func activate() { VoiceSession.shared.attach(self) }
  public func handle(_ event: NSEvent) -> Bool { activate(); return VoiceSession.shared.handle(event, context: self) }
  @objc public func toggle() { activate(); VoiceSession.shared.toggle() }
  public func deactivate() { VoiceSession.shared.detach(self) }
  @objc public func showPreferences() { VoicePreferences.shared.show() }
}

@MainActor final class VoiceSession {
  static let shared = VoiceSession()
  private weak var current: RimeVoiceController?
  private weak var inlineContext: RimeVoiceController?
  private var host: InputHost?
  private var editing = VoiceEditing()
  private var transcript = VoiceTranscript()
  private var formatter = VoiceTextFormatter(spaces: true, entries: [])
  private var currentAudioStart: Double?
  private var currentAudioEnd: Double?
  private var manualSegment: ClosedRange<Double>?
  private var previewOnly = false
  private var previewCanResume = false
  private var continuity = VoiceContextContinuity()
  private var process: Process?
  private var commands: FileHandle?
  private var session = ""
  private var sessionStartedAt = Date()
  private(set) var active = false
  private var stopping = false
  private var requestedRewrite: VoiceRewriteLevel?
  private var lastSequence: UInt64 = 0
  private var results: [[String: Any]] = []
  private var resultTask: Task<Void, Never>?
  private var stopAfterResults = false
  private var fixture: String?
  private var provider = "apple"
  private var cloudConfig: DoubaoConfiguration?
  private var ownerPID: pid_t = 0
  private var timer: Timer?
  private var permissionPending = false
  private var lastTrigger: TimeInterval = 0
  private let logger = Logger(subsystem: "im.rime.inputmethod.Squirrel", category: "Voice")
  private var hud: VoiceHUD?
  private var dismissTask: Task<Void, Never>?

  func startServices() {
    VoiceHistoryStore.shared.startCleanup()
    let shortcut = VoiceGlobalShortcut.shared
    shortcut.onTrigger = { [weak self] in self?.toggle() }
    shortcut.onEscape = { [weak self] in self?.cancel() }
    shortcut.isRecording = { [weak self] in self?.active == true }
    shortcut.onPointer = { [weak self] point in
      guard let self, self.active, !self.previewOnly,
            self.hud?.containsInteraction(at: point) != true else { return }
      // Revoke ownership immediately; do not leave a 50 ms overwrite window
      // while the application applies the click/selection change.
      self.protectManualEdit()
      let token = self.session
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
        guard let self, self.active, self.session == token else { return }
        self.checkInlineContext()
      }
    }
    shortcut.start()
  }
  func attach(_ context: RimeVoiceController) {
    current = context
    if active { checkInlineContext() }
  }
  func detach(_ context: RimeVoiceController) {
    if current?.id == context.id { current = nil }
    if active { checkInlineContext() }
  }
  func handle(_ event: NSEvent, context: RimeVoiceController) -> Bool {
    if event.type == .flagsChanged {
      if !VoiceGlobalShortcut.shared.installed { VoiceGlobalShortcut.shared.local(event) }
      return false
    }
    guard event.type == .keyDown else { return false }
    let mods = event.modifierFlags.intersection([.control, .shift, .option, .command])
    if mods == [.control, .shift] && event.keyCode == 49 { toggle(); return true }
    if event.keyCode == 53 && active { cancel(); return true }
    let shortcut = VoiceShortcut.configured
    if let key = shortcut.keyCode, key == event.keyCode,
       mods == shortcut.flags.intersection([.control, .shift, .option, .command]) {
      if !VoiceGlobalShortcut.shared.installed { toggle() }; return true
    }
    if active && !previewOnly { protectManualEdit() }
    if !VoiceGlobalShortcut.shared.installed { VoiceGlobalShortcut.shared.local(event) }
    return false
  }
  func acceptance(_ action: String) {
    switch action {
    case "start": if !active { toggle() }
    case "stop": if active && fixture != nil { stop() }
    case "cancel": if active && fixture != nil { cancel() }
    default: break
    }
  }
  func toggle() {
    let now = ProcessInfo.processInfo.systemUptime
    guard now - lastTrigger > 0.15 else { return }; lastTrigger = now
    if active { if !stopping { stop() }; return }
    RimeSlashUI.dismissForVoice()
    guard hud?.hasPendingResult != true else { status("请先处理上一段听写结果", temporary: true); return }
    provider = VoiceSettings.provider
    if provider == "apple" {
      guard #available(macOS 26, *) else { status("本地语音需要 macOS 26", temporary: true); return }
    }
    cloudConfig = nil
    if provider == "doubao" {
      let legacy = VoiceSettings.defaults.string(forKey: "doubaoAuthMode") == "legacy"
      let config = DoubaoConfiguration(apiKey: legacy ? "" : VoiceCredentials.read("apiKey") ?? "",
        appID: VoiceSettings.doubaoAppID, accessToken: legacy ? VoiceCredentials.read("accessToken") ?? "" : "",
        resource: VoiceSettings.doubaoResource, pauseMilliseconds: VoiceSettings.pauseMilliseconds, hotwords: VoiceDictionaryStore.shared.selectedHotwords, removeDisfluencies: VoiceSettings.removeDisfluencies)
      guard (try? config.request()) != nil else { status("豆包凭证暂不可用，请在配置页重新保存并允许钥匙串访问", temporary: true); return }
      cloudConfig = config
    }
    guard !IsSecureEventInputEnabled() else { status("请离开密码输入框后开始听写", temporary: true); return }
    fixture = VoiceSettings.acceptanceFixture
    if fixture == nil {
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .notDetermined:
        guard !permissionPending else { return }; permissionPending = true
        Task { [weak self] in
          let allowed = await AVCaptureDevice.requestAccess(for: .audio)
          self?.permissionPending = false
          self?.status(allowed ? "麦克风已授权，再按快捷键开始" : "请在系统设置中允许麦克风", temporary: true)
        }
        return
      case .authorized: break
      default: status("请在系统设置中允许鼠须管访问麦克风", temporary: true); return
      }
    }
    VoicePreferences.shared.stopPreview()
    formatter = VoiceDictionaryStore.shared.formatter
    requestedRewrite = nil
    editing = VoiceEditing(); transcript = VoiceTranscript(); continuity = VoiceContextContinuity(); currentAudioStart = nil; currentAudioEnd = nil; manualSegment = nil
    ownerPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
    previewOnly = true; previewCanResume = false; host = nil; inlineContext = nil
    if let current, !current.composing(), let client = current.clientProvider(),
       client.bundleIdentifier() == NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
      let candidate = InputHost(client)
      if editing.begin(candidate) {
        host = candidate; inlineContext = current; previewOnly = false; current.hideCandidates()
      }
    }
    sessionStartedAt = Date()
    session = UUID().uuidString; lastSequence = 0; active = true; stopping = false
    status(fixture == nil ? (provider == "apple" ? "正在启动本地语音…" : "正在连接豆包二遍识别…") : "听写验收 · 测试音频")
    do { try launch() } catch { cancel(); status("无法启动本地语音", temporary: true); return }
    timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.checkInlineContext() }
    }
    send("start")
  }
  private func launch() throws {
    let child = Process(), input = Pipe(), output = Pipe()
    child.executableURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/RimeVoice.app/Contents/MacOS/RimeVoice")
    child.standardInput = input; child.standardOutput = output; child.standardError = FileHandle.nullDevice
    let token = session
    child.terminationHandler = { [weak self] _ in
      DispatchQueue.main.async {
        guard let self, self.active, self.session == token else { return }
        if self.resultTask != nil { self.stopAfterResults = true } else { self.finishRecording() }
      }
    }
    try child.run(); process = child; commands = input.fileHandleForWriting
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      var pending = Data()
      while true {
        let data = output.fileHandleForReading.availableData
        if data.isEmpty { break }; pending.append(data)
        while let newline = pending.firstIndex(of: 10) {
          let line = pending.prefix(upTo: newline); pending.removeSubrange(...newline)
          guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
          DispatchQueue.main.async { self?.receive(event, token: token) }
        }
      }
    }
  }
  private func send(_ action: String) {
    var value = ["action": action, "session": session, "device": VoiceSettings.deviceUID, "channel": "0"]
    if let fixture { value["fixture"] = fixture }
    if action == "start" {
      value["provider"] = provider
      if let config = cloudConfig {
        value["apiKey"] = config.apiKey; value["appID"] = config.appID
        value["accessToken"] = config.accessToken; value["resource"] = config.resource
        value["pauseMilliseconds"] = String(config.pauseMilliseconds)
        value["removeDisfluencies"] = String(config.removeDisfluencies)
        if let words = try? JSONEncoder().encode(config.hotwords) { value["hotwords"] = String(decoding: words, as: UTF8.self) }
      }
    }
    guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
    try? commands?.write(contentsOf: data + Data([10]))
  }
  @discardableResult private func checkInlineContext() -> Bool {
    guard active else { return false }
    hud?.followInputScreen()
    if previewOnly {
      guard resumePreviewInline() else { return false }
    }
    let sameApplication = NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID && !IsSecureEventInputEnabled()
    if sameApplication, let candidateContext = current, candidateContext.id != inlineContext?.id,
       let client = candidateContext.clientProvider(),
       client.bundleIdentifier() == NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
      let candidate = InputHost(client)
      if editing.rebindComposition(to: candidate) {
        host = candidate; inlineContext = candidateContext
        logger.notice("Rebound the verified native composition after input-controller recreation")
      }
    }
    let client = inlineContext?.clientProvider()
    let attached = current != nil && current?.id == inlineContext?.id && client != nil && host != nil
    switch continuity.observe(sameApplication: sameApplication, attached: attached, now: ProcessInfo.processInfo.systemUptime) {
    case .preview: moveToPreview(reason: sameApplication ? .inputContextLost : .focusChange); return false
    case .waiting: return false
    case .ready: break
    }
    host?.client = client
    if !editing.confirming && (inlineContext?.composing() == true || !editing.validate()) { protectManualEdit() }
    return true
  }
  // A focus change during recording used to be a one-way trip to preview.
  // Once the original app has an editable native focus again, rebind a fresh
  // editing host and deliver subsequent results inline. The transcript's
  // delivered prefix keeps revisions from duplicating the sealed text.
  private func resumePreviewInline() -> Bool {
    guard previewCanResume, !stopping, !IsSecureEventInputEnabled(),
          let front = NSWorkspace.shared.frontmostApplication,
          front.processIdentifier == ownerPID,
          let context = current, !context.composing(),
          let client = context.clientProvider(),
          client.bundleIdentifier() == front.bundleIdentifier else { return false }
    let candidate = InputHost(client)
    guard editing.begin(candidate) else { return false }
    host = candidate; inlineContext = context; previewOnly = false; previewCanResume = false
    context.hideCandidates()
    hud?.endPreview()
    status("正在听写 · 已恢复输入框")
    logger.notice("Resumed inline delivery after the editable focus returned")
    return true
  }
  private func protectManualEdit() {
    editing.protect()
    if let start = currentAudioStart, let end = currentAudioEnd {
      manualSegment = start...max(start, end)
    }
    status("手动编辑已保护，下一段继续")
  }
  private func isProtected(_ start: Double) -> Bool {
    guard let range = manualSegment else { return false }
    // The end is exclusive: a new adjacent utterance may resume dictation.
    return start >= range.lowerBound - 0.0005 && start < range.upperBound - 0.0005
      || VoiceTranscript.key(start) == VoiceTranscript.key(range.lowerBound)
  }
  private func moveToPreview(reason: VoicePreviewReason) {
    guard active, !previewOnly else { return }
    let sealedText = editing.ownedMarkedText
    if editing.finish(), let start = currentAudioStart, let sealedText {
      transcript.deliveredPrefix(start: start, text: sealedText)
    }
    if let start = currentAudioStart, isProtected(start) { transcript.delivered(start: start) }
    previewOnly = true; previewCanResume = reason.canResume; host = nil; inlineContext = nil
    status(reason == .writeUnconfirmed ? "输入框未确认写入 · 录音继续" : "录音继续 · 文字在浮窗预览")
    hud?.preview(formatter.format(transcript.remaining))
    logger.notice("Recording continues in floating preview: \(reason.rawValue, privacy: .public), canResume=\(reason.canResume)")
  }
  private func receive(_ event: [String: Any], token: String) {
    guard active, token == session, event["session"] as? String == session,
          let sequence = event["sequence"] as? UInt64, sequence > lastSequence else { return }
    lastSequence = sequence; checkInlineContext()
    switch event["type"] as? String {
    case "listening": status(fixture == nil ? (provider == "apple" ? "正在听写 · 本地" : "正在听写 · 豆包二遍") : "听写验收 · 测试音频")
    case "audio": if let level = event["level"] as? Double { hud?.audio(level) }
    case "result":
      results.append(event)
      drainResults(token: token)
    case "stopped":
      if resultTask != nil { stopAfterResults = true } else { finishRecording() }
    case "error":
      let message = event["message"] as? String ?? "识别已停止"
      finishRecording(); status(message, temporary: true, duration: 15)
    default: break
    }
  }
  private func drainResults(token: String) {
    guard resultTask == nil else { return }
    resultTask = Task { @MainActor [weak self] in
      guard let self else { return }
      while self.active, self.session == token, !Task.isCancelled, !self.results.isEmpty {
        let event = self.results.removeFirst()
        self.checkInlineContext()
        await self.receiveResult(event, token: token)
      }
      guard self.session == token else { return }
      self.resultTask = nil
      if self.stopAfterResults { self.stopAfterResults = false; self.finishRecording() }
    }
  }
  private func receiveResult(_ event: [String: Any], token: String) async {
    // Electron can briefly recreate its input controller while the field
    // remains focused. Wait without mutating until ownership is re-established.
    while active && session == token && !Task.isCancelled && !previewOnly && !checkInlineContext() {
      try? await Task.sleep(nanoseconds: 40_000_000)
    }
    guard active, session == token, !Task.isCancelled else { return }
    guard let rawText = event["text"] as? String, let final = event["final"] as? Bool,
          let start = event["start"] as? Double, let end = event["end"] as? Double else { return }
    let text = formatter.format(rawText, voice: true, previous: previewOnly || isProtected(start) ? "" : editing.leadingContext, previousAtStart: editing.leadingContextAtStart)
    currentAudioStart = start; currentAudioEnd = end
    transcript.update(text: text, start: start, end: end, final: final)
    hud?.setRewriteSource(transcript.all)
    saveHistory(state: "recording")
    if transcript.wasDelivered(start: start) && !isProtected(start) { return }
    if isProtected(start) {
      // Finalize the protected audio segment without touching an active Rime composition.
      if final && editing.suppressed { _ = editing.receive(text, final: true) }
      transcript.delivered(start: start)
    } else if !previewOnly, current?.composing() == false {
      if editing.suppressed {
        guard let range = manualSegment, start >= range.upperBound - 0.0005,
              editing.resumeAfterManualEdit() else {
          moveToPreview(reason: .manualEdit); hud?.preview(formatter.format(transcript.remaining)); return
        }
      }
      transcript.inlineWriteAttempted()
      // After a focus transition the sealed prefix is already in the field;
      // only its tail may be written inline. A revision that disagrees with
      // the sealed prefix stays in preview instead of overwriting it.
      guard let inlineText = transcript.inlineRemainder(start: start, text: text) else {
        moveToPreview(reason: .revisionMismatch)
        hud?.preview(formatter.format(transcript.remaining))
        return
      }
      let accepted = await editing.receiveConfirmed(inlineText, final: final)
      guard active, session == token, !Task.isCancelled else { return }
      if !accepted && isProtected(start) {
        transcript.delivered(start: start)
        return
      }
      if final && accepted { transcript.delivered(start: start) }
      // Never write later speech ahead of a result we could not safely
      // deliver. Keep the whole remaining tail in chronological preview.
      if !accepted { moveToPreview(reason: .writeUnconfirmed); hud?.preview(formatter.format(transcript.remaining)) }
      logger.info("Inline recognition event: final=\(final), accepted=\(accepted)")
    } else {
      if !previewOnly { moveToPreview(reason: current?.composing() == true ? .composing : .inputContextLost) }
      hud?.preview(formatter.format(transcript.remaining))
    }
  }
  private func stop() {
    stopping = true; status("正在完成听写…"); send("stop")
    let token = session
    Task { [weak self] in
      try? await Task.sleep(nanoseconds: 12_000_000_000)
      guard let self, self.active, self.session == token else { return }; self.finishRecording()
    }
  }
  private func closeProcess() {
    active = false; stopping = false; send("cancel")
    resultTask?.cancel(); resultTask = nil; results.removeAll(); stopAfterResults = false
    try? commands?.close(); commands = nil
    let child = process; process = nil
    Task { try? await Task.sleep(nanoseconds: 500_000_000); if child?.isRunning == true { child?.terminate() } }
    cloudConfig = nil
    timer?.invalidate(); timer = nil; hud?.hide()
  }
  private func saveHistory(state: String) {
    // Fixtures are test data, and never belong in the user's history.
    guard fixture == nil else { return }
    VoiceHistoryStore.shared.update(id: session, startedAt: sessionStartedAt, text: transcript.all, state: state)
  }
  private func finishRecording() {
    guard active else { return }
    saveHistory(state: "completed")
    if !previewOnly {
      let sealed = editing.finish()
      if let start = currentAudioStart, sealed || isProtected(start) { transcript.delivered(start: start) }
    }
    let rewriteLevel = requestedRewrite; requestedRewrite = nil
    closeProcess()
    let source = transcript.all
    hud?.setRewriteSource(source)
    if let rewriteLevel { hud?.performRewrite(source, level: rewriteLevel); return }
    let remaining = formatter.format(transcript.remaining)
    // Normal completion is silent, whether nothing was recognized or all
    // recognized text was already delivered. closeProcess() has hidden the HUD.
    if remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
    // A failed acknowledgement does not prove the previous write failed.
    // Once inline delivery was attempted, replaying at stop can duplicate it.
    guard transcript.allowsAutomaticFinalInsertion else { hud?.showResult(remaining); return }
    let target: (any VoiceTextHost)?
    if current?.composing() == true {
      target = nil
    } else if let current, !current.composing(), let client = current.clientProvider(),
       client.bundleIdentifier() == NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
      target = InputHost(client)
    } else { target = VoiceAccessibilityHost.focused() }
    let writer = VoiceEditing()
    if let target, writer.begin(target), writer.receive(remaining, final: true) {
      return
    } else { hud?.showResult(remaining) }
  }
  func rewriteHistory(_ text: String, level: VoiceRewriteLevel) {
    guard !active else { status("请先结束当前听写，再重写历史记录"); return }
    dismissTask?.cancel(); dismissTask = nil
    status("正在准备文字重写…")
    hud?.performRewrite(text, level: level)
  }
  func cancel() {
    guard active else { return }
    requestedRewrite = nil
    saveHistory(state: "cancelled")
    dismissTask?.cancel(); dismissTask = nil; hud?.hide()
    if !previewOnly { editing.cancelUnedited() }
    closeProcess(); transcript = VoiceTranscript()
  }
  private func status(_ text: String, temporary: Bool = false, duration: Double = 3) {
    dismissTask?.cancel()
    if hud == nil {
      let hud = VoiceHUD()
      hud.inputAnchor = { [weak self] in
        guard let context = self?.current, let client = context.clientProvider(),
              client.bundleIdentifier() == NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return nil }
        var rect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        guard rect.width.isFinite, rect.height.isFinite, rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width > 0 || rect.height > 0 else { return nil }
        return rect
      }
      hud.onStop = { [weak self] in self?.stop() }
      hud.onCancel = { [weak self] in self?.cancel() }
      hud.onRewrite = { [weak self] level in
        guard let self, self.active, !self.stopping else { return }
        self.requestedRewrite = level; self.stop()
      }
      self.hud = hud
    }
    hud?.show(text, recording: active)
    if temporary {
      dismissTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        guard !Task.isCancelled, self?.active != true, self?.hud?.hasPendingResult != true else { return }; self?.hud?.hide()
      }
    }
  }
}
