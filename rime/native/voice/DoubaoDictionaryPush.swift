import AppKit
import Foundation

enum DoubaoPushOperation: Equatable {
  case preview
  case apply
  case version
  var argument: String {
    switch self {
    case .preview: return "--preview"
    case .apply: return "--apply"
    case .version: return "--version"
    }
  }
}

struct DoubaoPushCandidate: Equatable {
  let index: Int
  let output: String
  let code: String
  let weight: String
}

struct DoubaoPushPreviewRow: Equatable {
  let index: Int
  let output: String
  let input: String
  let split: String
  let source: String
  let status: String
  var selectable: Bool { status == "ok" }
  var sourceText: String {
    switch source {
    case "canonical": return "规范拼音"
    case "code": return "编码分段"
    case "system": return "系统转换"
    case "explicit": return "显式分段"
    case "ambiguous": return "歧义（建议核对）"
    default: return source.isEmpty ? "-" : source
    }
  }
  var statusText: String {
    switch status {
    case "ok": return "可添加"
    case "exists": return "已存在"
    case "invalid_pinyin": return "拼音无法识别"
    case "skipped": return "跳过"
    case "error": return "错误"
    default: return status
    }
  }
}

struct DoubaoPushApplyResult: Equatable {
  let added: Int
  let exists: Int
  let skipped: Int
  let failed: Int
  let backup: String
}

enum DoubaoPushError: LocalizedError {
  case helperMissing
  case helperFailed(String)
  case doubaoRunning
  var errorDescription: String? {
    switch self {
    case .helperMissing:
      return "推送助手未安装：请在终端运行 `bash rime/tools/build_doubao_push.sh`。"
    case .helperFailed(let message):
      return message
    case .doubaoRunning:
      return "豆包仍在运行：请手动退出豆包（活动监视器 → DoubaoIme → 退出）后重试。"
    }
  }
}

enum DoubaoPushPlan {
  static let helperRelativePath = "Library/Application Support/Squirrel/DoubaoPush/doubao_push"

  static var helperURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(helperRelativePath)
  }

  static var helperInstalled: Bool {
    FileManager.default.isExecutableFile(atPath: helperURL.path)
  }

  static func candidates(from entries: [VoiceDictionaryEntry]) -> [DoubaoPushCandidate] {
    var seen = Set<String>()
    var result: [DoubaoPushCandidate] = []
    for entry in entries {
      let output = entry.output
      guard !entry.code.isEmpty,
            !output.isEmpty,
            output.utf16.count <= 64,
            !output.contains(where: { $0.isNewline || $0 == "\t" }),
            !output.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
            !entry.code.contains(where: { $0.isNewline || $0 == "\t" }) else { continue }
      let key = output + "\t" + entry.code
      guard seen.insert(key).inserted else { continue }
      result.append(.init(index: result.count, output: output, code: entry.code, weight: entry.weight))
    }
    return result
  }

  static func inputTSV(_ candidates: [DoubaoPushCandidate]) -> String {
    candidates.map { $0.output + "\t" + $0.code + "\t" + $0.weight }.joined(separator: "\n") + "\n"
  }

  static func parsePreview(_ text: String) -> [DoubaoPushPreviewRow] {
    var rows: [DoubaoPushPreviewRow] = []
    for line in text.components(separatedBy: .newlines) where line.hasPrefix("P\t") {
      let fields = line.components(separatedBy: "\t")
      guard fields.count == 7, let index = Int(fields[1]) else { continue }
      rows.append(.init(index: index, output: fields[2], input: fields[3], split: fields[4],
                        source: fields[5], status: fields[6]))
    }
    return rows.sorted { $0.index < $1.index }
  }

  static func parseApply(_ text: String) -> DoubaoPushApplyResult? {
    guard let line = text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("A\t") }) else { return nil }
    var values: [String: String] = [:]
    for field in line.components(separatedBy: "\t").dropFirst() {
      guard let equals = field.firstIndex(of: "=") else { continue }
      values[String(field[..<equals])] = String(field[field.index(after: equals)...])
    }
    guard let added = values["added"].flatMap(Int.init),
          let exists = values["exists"].flatMap(Int.init),
          let skipped = values["skipped"].flatMap(Int.init),
          let failed = values["failed"].flatMap(Int.init) else { return nil }
    return .init(added: added, exists: exists, skipped: skipped, failed: failed, backup: values["backup"] ?? "")
  }

  static func helperError(from stderr: String) -> (name: String, message: String)? {
    for line in stderr.components(separatedBy: .newlines) where line.hasPrefix("E\t") {
      let fields = line.components(separatedBy: "\t")
      guard fields.count >= 2 else { continue }
      return (fields[1], fields.count >= 3 ? fields[2...].joined(separator: "\t") : "")
    }
    return nil
  }

  static func localizedError(name: String, message: String) -> String {
    switch name {
    case "engine_missing", "engine_load_failed", "engine_symbol_missing":
      return "没有找到可用的 Mac 豆包引擎；请先安装并启动豆包输入法。"
    case "engine_mismatch":
      return "豆包已升级，推送助手需要更新：请重新运行 `bash rime/tools/build_doubao_push.sh`。"
    case "account_missing", "dictionary_missing":
      return "找不到豆包个人词库；请先在 Mac 豆包输入一次中文，让豆包创建词库后再试。"
    case "account_ambiguous":
      return "发现多个豆包账号词库，暂不支持自动选择。"
    case "doubao_running":
      return "豆包仍在运行；请手动退出豆包后重试。"
    case "changing", "live_changed":
      return "豆包词库正在更新；请重新生成预览后再推送。"
    case "save_failed", "reload_failed", "verify_failed", "pruned", "backup_mismatch", "rename_failed":
      return "写入校验失败，未修改豆包词库；请重新预览后重试。"
    default:
      return message.isEmpty ? "推送助手失败（\(name)）。" : message
    }
  }
}

@MainActor final class DoubaoDictionaryPush: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  static let shared = DoubaoDictionaryPush()

  typealias Runner = @Sendable (_ operation: DoubaoPushOperation, _ input: String) throws -> (stdout: String, stderr: String, status: Int32)

  private let runner: Runner
  private var panel: NSPanel?
  private let table = NSTableView()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let spinner = NSProgressIndicator()
  private var pushButton: NSButton!
  private var reloadButton: NSButton!
  private var allButton: NSButton!
  private var cancelButton: NSButton!
  private var entries: [VoiceDictionaryEntry] = []
  private var candidates: [DoubaoPushCandidate] = []
  private var rows: [DoubaoPushPreviewRow] = []
  private var candidatesByIndex: [Int: DoubaoPushCandidate] = [:]
  private var generation = UUID()
  private var completion: ((String) -> Void)?
  private var confirming = false
  private var applying = false

  init(runner: @escaping Runner = DoubaoDictionaryPush.defaultRunner) {
    self.runner = runner
    super.init()
  }

  func show(parent: NSWindow, entries: [VoiceDictionaryEntry], completion: ((String) -> Void)? = nil) {
    if panel == nil { create() }
    self.entries = entries
    self.completion = completion
    confirming = false
    applying = false
    rows = []; candidates = []; candidatesByIndex = [:]
    table.reloadData()
    updateButtons()
    parent.beginSheet(panel!)
    reload()
  }

  private func create() {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                        styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    panel.title = "推送到豆包"
    panel.minSize = NSSize(width: 700, height: 460)
    panel.isReleasedWhenClosed = false
    self.panel = panel
    let root = panel.contentView!
    let explanation = NSTextField(wrappingLabelWithString:
      "只推送自定义短语中的条目；汉字词和带有效拼音编码的英文/邮箱词都会推送，编码无法识别为拼音的条目会标记失败。拼音列显示实际输入编码，同一编码可对应全名和简称。会写入 Mac 豆包个人词库，并经豆包账号同步到手机；iPhone 通常约 1–2 小时出现，取决于两端调度，想尽快可尝试在 iPhone 豆包“我的”关闭再打开“数据同步”。豆包原词库会先备份。")
    explanation.frame = NSRect(x: 20, y: 455, width: 740, height: 62)
    explanation.autoresizingMask = [.width, .minYMargin]
    root.addSubview(explanation)

    let scroll = NSScrollView(frame: NSRect(x: 20, y: 110, width: 740, height: 332))
    scroll.hasVerticalScroller = true
    scroll.autoresizingMask = [.width, .height]
    scroll.borderType = .bezelBorder
    for (id, title, width) in [("word", "词", 250.0), ("pinyin", "拼音", 230.0),
                                ("source", "来源", 125.0), ("status", "状态", 115.0)] {
      let column = NSTableColumn(identifier: .init(id))
      column.title = title
      column.width = width
      table.addTableColumn(column)
    }
    table.allowsMultipleSelection = true
    table.usesAlternatingRowBackgroundColors = true
    table.rowHeight = 25
    table.dataSource = self
    table.delegate = self
    scroll.documentView = table
    root.addSubview(scroll)

    status.frame = NSRect(x: 20, y: 58, width: 700, height: 44)
    status.font = .systemFont(ofSize: 11)
    status.autoresizingMask = [.width]
    root.addSubview(status)

    spinner.style = .spinning
    spinner.controlSize = .small
    spinner.isDisplayedWhenStopped = false
    spinner.frame = NSRect(x: 738, y: 78, width: 18, height: 18)
    spinner.autoresizingMask = [.minXMargin]
    root.addSubview(spinner)

    func button(_ title: String, _ action: Selector, _ x: CGFloat, _ width: CGFloat) -> NSButton {
      let button = NSButton(title: title, target: self, action: action)
      button.bezelStyle = .rounded
      button.frame = NSRect(x: x, y: 14, width: width, height: 30)
      root.addSubview(button)
      return button
    }
    allButton = button("全选可添加", #selector(selectAll), 20, 120)
    reloadButton = button("重新生成预览", #selector(reload), 148, 125)
    cancelButton = button("取消", #selector(close), 500, 90)
    cancelButton.keyEquivalent = "\u{1b}"
    cancelButton.autoresizingMask = [.minXMargin]
    pushButton = button("推送所选", #selector(push), 598, 162)
    pushButton.autoresizingMask = [.minXMargin]
  }

  @objc private func reload() {
    guard !applying else { return }
    let token = UUID()
    generation = token
    confirming = false
    rows = []
    candidates = []
    candidatesByIndex = [:]
    table.reloadData()
    pushButton.title = "推送所选"
    updateButtons()
    guard DoubaoPushPlan.helperInstalled else {
      status.stringValue = DoubaoPushError.helperMissing.localizedDescription
      return
    }
    candidates = DoubaoPushPlan.candidates(from: entries)
    guard !candidates.isEmpty else {
      status.stringValue = "没有可推送的自定义短语（需要包含汉字并填写拼音编码）。"
      return
    }
    candidatesByIndex = Dictionary(uniqueKeysWithValues: candidates.map { ($0.index, $0) })
    let input = DoubaoPushPlan.inputTSV(candidates)
    let runner = self.runner
    status.stringValue = "正在读取本机豆包词库…"
    spinner.startAnimation(nil)
    reloadButton.isEnabled = false
    allButton.isEnabled = false
    pushButton.isEnabled = false
    Task { [weak self] in
      let result = await Task.detached(priority: .userInitiated) {
        Result { try runner(.preview, input) }
      }.value
      guard let self, self.generation == token, !self.applying else { return }
      self.spinner.stopAnimation(nil)
      self.reloadButton.isEnabled = true
      switch result {
      case .failure(let error):
        self.status.stringValue = error.localizedDescription
      case .success(let output):
        if output.status != 0 {
          self.status.stringValue = self.helperMessage(output)
          return
        }
        let parsed = DoubaoPushPlan.parsePreview(output.stdout)
        guard !parsed.isEmpty else {
          self.status.stringValue = "没有可推送的词条；请检查拼音编码。"
          return
        }
        self.rows = parsed
        self.table.reloadData()
        self.selectAll()
        let addable = parsed.filter(\.selectable).count
        let existing = parsed.filter { $0.status == "exists" }.count
        let failed = parsed.filter { $0.status == "invalid_pinyin" || $0.status == "error" }.count
        let skipped = parsed.filter { $0.status == "skipped" }.count
        self.status.stringValue = "可添加 \(addable)，已存在 \(existing)，拼音失败 \(failed)，跳过 \(skipped)。预览基于当前已保存的豆包词库，推送时会重新检查。"
      }
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    guard rows.indices.contains(row) else { return nil }
    let item = rows[row]
    switch tableColumn?.identifier.rawValue {
    case "pinyin": return item.split
    case "source": return item.sourceText
    case "status": return item.statusText
    default: return item.output
    }
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    rows.indices.contains(row) && rows[row].selectable
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    updateButtons()
  }

  @objc private func selectAll() {
    let indexes = IndexSet(rows.indices.filter { rows[$0].selectable })
    table.selectRowIndexes(indexes, byExtendingSelection: false)
    updateButtons()
  }

  @objc private func push() {
    guard !applying else { return }
    let selected = table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil }
      .filter(\.selectable)
      .compactMap { candidatesByIndex[$0.index] }
    guard !selected.isEmpty else {
      status.stringValue = "请先选择可添加的词条。"
      return
    }
    if !confirming {
      confirming = true
      pushButton.title = "确认推送"
      status.stringValue = "推送前请先切换到鼠须管。继续后会正常退出豆包进程；完成后切回豆包输入一次中文。点击“确认推送”继续，或点“取消”关闭。"
      return
    }
    confirming = false
    pushButton.title = "推送所选"
    let input = DoubaoPushPlan.inputTSV(selected)
    let runner = self.runner
    applying = true
    setApplying(true)
    status.stringValue = "正在写入 Mac 豆包词库…"
    spinner.startAnimation(nil)
    Task { [weak self] in
      guard let self else { return }
      var stoppedDoubao = false
      do {
        let version = try await Task.detached(priority: .userInitiated) {
          try runner(.version, "")
        }.value
        guard version.status == 0, version.stdout.contains("engine_ok=1") else {
          throw DoubaoPushError.helperFailed(self.helperMessage(version))
        }
        stoppedDoubao = try await self.terminateDoubao()
        let output = try await Task.detached(priority: .userInitiated) {
          try runner(.apply, input)
        }.value
        guard output.status == 0, let summary = DoubaoPushPlan.parseApply(output.stdout) else {
          throw DoubaoPushError.helperFailed(self.helperMessage(output))
        }
        self.spinner.stopAnimation(nil)
        self.applying = false
        self.setApplying(false)
        let message = "已写入 \(summary.added) 条；备份：\(summary.backup)。请切回豆包输入一次中文；Mac 端下次调度上传，iPhone 通常约 1–2 小时出现，取决于两端调度。首次推送使用默认词频；若候选靠后，在豆包中选一次即可提频。"
        self.status.stringValue = message
        self.completion?(message)
        self.reloadButton.isEnabled = true
        self.allButton.isEnabled = true
        self.updateButtons()
      } catch {
        self.spinner.stopAnimation(nil)
        self.applying = false
        self.setApplying(false)
        self.status.stringValue = error.localizedDescription + (stoppedDoubao ? " 豆包已停止；切回豆包会重新启动。" : "")
        self.reloadButton.isEnabled = true
        self.allButton.isEnabled = true
        self.updateButtons()
      }
    }
  }

  private func setApplying(_ value: Bool) {
    cancelButton.isEnabled = !value
    reloadButton.isEnabled = !value
    allButton.isEnabled = !value
    pushButton.isEnabled = !value && !table.selectedRowIndexes.isEmpty
    panel?.standardWindowButton(.closeButton)?.isEnabled = !value
  }

  private func updateButtons() {
    allButton.isEnabled = !applying && !rows.isEmpty
    pushButton.isEnabled = !applying && !table.selectedRowIndexes.isEmpty
    reloadButton.isEnabled = !applying
  }

  private func terminateDoubao() async throws -> Bool {
    let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.bytedance.inputmethod.doubaoime")
    guard !apps.isEmpty else { return false }
    for app in apps { _ = app.terminate() }
    for _ in 0..<25 {
      try await Task.sleep(nanoseconds: 200_000_000)
      if apps.allSatisfy(\.isTerminated) { return true }
    }
    throw DoubaoPushError.doubaoRunning
  }

  private func helperMessage(_ output: (stdout: String, stderr: String, status: Int32)) -> String {
    if let failure = DoubaoPushPlan.helperError(from: output.stderr) {
      return DoubaoPushPlan.localizedError(name: failure.name, message: failure.message)
    }
    return output.status == 0 ? "推送助手返回了无法识别的结果。" : "推送助手失败（退出码 \(output.status)）。"
  }

  @objc private func close() {
    guard !applying else { return }
    generation = UUID()
    spinner.stopAnimation(nil)
    confirming = false
    pushButton.title = "推送所选"
    if let panel {
      panel.sheetParent?.endSheet(panel)
      panel.orderOut(nil)
    }
    completion = nil
  }

  nonisolated static let defaultRunner: Runner = { operation, input in
    let url = DoubaoPushPlan.helperURL
    guard FileManager.default.isExecutableFile(atPath: url.path) else {
      throw DoubaoPushError.helperMissing
    }
    let process = Process()
    process.executableURL = url
    process.arguments = [operation.argument]
    let inputPipe = Pipe(), outputPipe = Pipe(), errorPipe = Pipe()
    process.standardInput = inputPipe
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    try process.run()
    if operation != .version {
      if let data = input.data(using: .utf8) {
        try? inputPipe.fileHandleForWriting.write(contentsOf: data)
      }
    }
    try? inputPipe.fileHandleForWriting.close()
    let watchdog = DispatchWorkItem {
      if process.isRunning { process.terminate() }
    }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + (operation == .apply ? 90.0 : 30.0), execute: watchdog)
    let outData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    watchdog.cancel()
    return (String(data: outData, encoding: .utf8) ?? "",
            String(data: errData, encoding: .utf8) ?? "",
            process.terminationStatus)
  }
}
