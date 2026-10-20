import AppKit

@MainActor final class DoubaoDictionaryImport: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
  static let shared = DoubaoDictionaryImport()
  private let read: @Sendable () throws -> DoubaoDictionaryReader.Snapshot
  init(read: @escaping @Sendable () throws -> DoubaoDictionaryReader.Snapshot = { try DoubaoDictionaryReader.load() }) {
    self.read = read; super.init()
  }
  private var panel: NSPanel?
  private let table = NSTableView()
  private let search = NSSearchField()
  private let status = NSTextField(wrappingLabelWithString: "")
  private let spinner = NSProgressIndicator()
  private var mergeButton: NSButton!
  private var reloadButton: NSButton!
  private var allButton: NSButton!
  private var words: [DoubaoDictionaryWord] = [], visible: [DoubaoDictionaryWord] = []
  private var local: [VoiceDictionaryEntry] = []
  private var excluded = Set<String>()
  private var generation = UUID()
  private var completion: (([VoiceDictionaryEntry]) -> Void)?
  func show(parent: NSWindow, local: [VoiceDictionaryEntry], excluded: Set<String>, completion: @escaping ([VoiceDictionaryEntry]) -> Void) {
    if panel == nil { create() }
    self.local = local; self.excluded = excluded; self.completion = completion
    search.stringValue = ""; words = []; visible = []; table.reloadData()
    parent.beginSheet(panel!)
    reload()
  }
  private func create() {
    let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 510), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    panel.title = "从豆包合并词库"; panel.minSize = NSSize(width: 660, height: 400); panel.isReleasedWhenClosed = false; self.panel = panel
    let root = panel.contentView!
    let explanation = NSTextField(wrappingLabelWithString: "读取 Mac 豆包已下载的个人词库（含已同步到 Mac 的手机词）。只向本地词典添加；同名词、手工词编码冲突保留本地设置，新增词不勾选语音热词。")
    explanation.frame = NSRect(x: 20, y: 450, width: 720, height: 42); explanation.autoresizingMask = [.width, .minYMargin]; root.addSubview(explanation)
    search.frame = NSRect(x: 20, y: 410, width: 720, height: 28); search.placeholderString = "搜索词条或拼音，支持多选"; search.delegate = self
    search.autoresizingMask = [.width, .minYMargin]; root.addSubview(search)
    let scroll = NSScrollView(frame: NSRect(x: 20, y: 114, width: 720, height: 282)); scroll.hasVerticalScroller = true
    scroll.autoresizingMask = [.width, .height]; scroll.borderType = .bezelBorder
    for (id, title, width) in [("word", "待新增词条", 285.0), ("code", "拼音编码", 280.0), ("source", "豆包来源", 120.0)] {
      let c = NSTableColumn(identifier: .init(id)); c.title = title; c.width = width; table.addTableColumn(c)
    }
    table.allowsMultipleSelection = true; table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 25
    table.dataSource = self; table.delegate = self; scroll.documentView = table; root.addSubview(scroll)
    status.frame = NSRect(x: 20, y: 55, width: 690, height: 48); status.font = .systemFont(ofSize: 11)
    status.autoresizingMask = [.width]; root.addSubview(status)
    spinner.style = .spinning; spinner.controlSize = .small; spinner.isDisplayedWhenStopped = false
    spinner.frame = NSRect(x: 718, y: 75, width: 18, height: 18); spinner.autoresizingMask = [.minXMargin]; root.addSubview(spinner)
    func button(_ title: String, _ action: Selector, _ x: CGFloat, _ width: CGFloat) -> NSButton {
      let b = NSButton(title: title, target: self, action: action); b.bezelStyle = .rounded
      b.frame = NSRect(x: x, y: 14, width: width, height: 30); root.addSubview(b); return b
    }
    allButton = button("全选当前结果", #selector(selectAll), 20, 130)
    reloadButton = button("重新读取", #selector(reload), 158, 100)
    let cancel = button("取消", #selector(close), 470, 90); cancel.keyEquivalent = "\u{1b}"; cancel.autoresizingMask = [.minXMargin]
    mergeButton = button("合并所选到词典", #selector(merge), 565, 175); mergeButton.autoresizingMask = [.minXMargin]
  }
  @objc private func reload() {
    let token = UUID(); generation = token
    words = []; visible = []; table.reloadData(); mergeButton.isEnabled = false; allButton.isEnabled = false; reloadButton.isEnabled = false
    status.stringValue = "正在读取本机词库…"; spinner.startAnimation(nil)
    let reader = read
    Task { [weak self] in
      let result = await Task.detached(priority: .userInitiated) { Result { try reader() } }.value
      guard let self, self.generation == token else { return }
      self.spinner.stopAnimation(nil); self.reloadButton.isEnabled = true
      switch result {
      case .failure(let error): self.status.stringValue = error.localizedDescription
      case .success(let snapshot):
        let plan = DoubaoDictionaryMerge.plan(local: self.local, incoming: snapshot.words, excluding: self.excluded)
        let ids = Set(plan.additions.compactMap(\.doubaoImportID))
        var seen = Set<String>()
        self.words = snapshot.words.filter { ids.contains($0.id) && seen.insert($0.id).inserted }
        self.applySearch()
        self.status.stringValue = "读取 \(snapshot.records) 条；可新增 \(plan.additions.count) 条，保留本地/编码冲突或重复 \(plan.retained) 条，本地已删除 \(plan.suppressed) 条，未支持或无有效词频 \(snapshot.skipped) 条。\n仅合并所选，返回后点击“保存并部署”生效；不向豆包写入或删除。"
      }
    }
  }
  private func applySearch() {
    let query = search.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    visible = query.isEmpty ? words : words.filter { $0.output.localizedCaseInsensitiveContains(query) || $0.code.localizedCaseInsensitiveContains(query) }
    table.deselectAll(nil); table.reloadData(); allButton.isEnabled = !visible.isEmpty; mergeButton.isEnabled = false
  }
  func controlTextDidChange(_ notification: Notification) { applySearch() }
  func numberOfRows(in tableView: NSTableView) -> Int { visible.count }
  func tableView(_ tableView: NSTableView, objectValueFor column: NSTableColumn?, row: Int) -> Any? {
    let word = visible[row]
    switch column?.identifier.rawValue {
    case "code": return word.code
    case "source": return word.platforms == 1 ? "手机" : word.platforms == 2 ? "电脑" : "手机、电脑"
    default: return word.output
    }
  }
  func tableViewSelectionDidChange(_ notification: Notification) { mergeButton.isEnabled = !table.selectedRowIndexes.isEmpty }
  @objc private func selectAll() { table.selectAll(nil) }
  @objc private func merge() {
    let selected = table.selectedRowIndexes.compactMap { visible.indices.contains($0) ? visible[$0] : nil }
    let plan = DoubaoDictionaryMerge.plan(local: local, incoming: selected, excluding: excluded)
    let callback = completion; close(); callback?(plan.additions)
  }
  @objc private func close() {
    generation = UUID(); spinner.stopAnimation(nil)
    if let panel { panel.sheetParent?.endSheet(panel); panel.orderOut(nil) }
    completion = nil
  }
}
