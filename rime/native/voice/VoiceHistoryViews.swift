import AppKit

@MainActor final class VoiceHistoryPreferences: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  static let shared = VoiceHistoryPreferences(store: VoiceHistoryStore.shared)
  private let store: VoiceHistoryStore
  var writeClipboard: (String) -> Void = { text in
    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
  }
  init(store: VoiceHistoryStore) { self.store = store; super.init() }
  private var window: NSWindow?
  private let table = NSTableView()
  private let detail = NSTextView()
  private let summary = NSTextField(labelWithString: "")
  private let copyButton = NSButton(title: "复制全文", target: nil, action: nil)
  private let deleteButton = NSButton(title: "删除此条", target: nil, action: nil)
  private var entries: [VoiceHistoryEntry] = []
  private var observer: NSObjectProtocol?
  private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter(); formatter.dateFormat = "MM-dd HH:mm:ss"; return formatter
  }()
  func show() {
    if window == nil { createWindow() }
    reload(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  private func createWindow() {
    let window = VoiceEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    window.title = "听写历史"; window.isReleasedWhenClosed = false; window.center(); self.window = window
    guard let root = window.contentView else { return }
    summary.frame = NSRect(x: 22, y: 518, width: 676, height: 24)
    summary.font = .systemFont(ofSize: 12); summary.textColor = .secondaryLabelColor; root.addSubview(summary)
    let list = NSScrollView(frame: NSRect(x: 22, y: 290, width: 676, height: 218))
    list.hasVerticalScroller = true; list.borderType = .bezelBorder
    for (id, title, width) in [("time", "时间 / 状态", CGFloat(158)), ("text", "识别内容", CGFloat(490))] {
      let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width
      table.addTableColumn(column)
    }
    table.rowHeight = 42; table.delegate = self; table.dataSource = self
    list.documentView = table; root.addSubview(list)
    let content = NSScrollView(frame: NSRect(x: 22, y: 66, width: 676, height: 210))
    content.hasVerticalScroller = true; content.borderType = .bezelBorder
    detail.isEditable = false; detail.isSelectable = true; detail.isRichText = false
    detail.font = .systemFont(ofSize: 15); detail.textContainerInset = NSSize(width: 10, height: 10)
    detail.isVerticallyResizable = true; detail.isHorizontallyResizable = false
    detail.autoresizingMask = [.width]; detail.textContainer?.widthTracksTextView = true
    detail.frame = content.bounds; content.documentView = detail; root.addSubview(content)
    copyButton.frame = NSRect(x: 22, y: 20, width: 108, height: 32)
    copyButton.target = self; copyButton.action = #selector(copyText); copyButton.bezelStyle = .rounded; root.addSubview(copyButton)
    deleteButton.frame = NSRect(x: 140, y: 20, width: 108, height: 32)
    deleteButton.target = self; deleteButton.action = #selector(deleteEntry); deleteButton.bezelStyle = .rounded; root.addSubview(deleteButton)
    let clear = NSButton(title: "清空历史", target: self, action: #selector(clearEntries))
    clear.bezelStyle = .rounded; clear.frame = NSRect(x: 590, y: 20, width: 108, height: 32); root.addSubview(clear)
    observer = NotificationCenter.default.addObserver(forName: VoiceHistoryStore.changed, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.reload() }
    }
  }
  private func reload() {
    let selectedID = selected?.id
    entries = store.entries
    table.reloadData()
    let index = selectedID.flatMap { id in entries.firstIndex { $0.id == id } } ?? (entries.isEmpty ? nil : 0)
    if let index { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
    else { table.deselectAll(nil) }
    summary.stringValue = store.saveFailed ? "历史保存失败，请检查本机存储空间与目录权限。" : "仅保存在本机 · 超过 24 小时自动删除 · 包含已取消听写 · 不含手动修改"
    displaySelection()
  }
  private var selected: VoiceHistoryEntry? { entries.indices.contains(table.selectedRow) ? entries[table.selectedRow] : nil }
  private func displaySelection() {
    detail.string = selected?.text ?? "暂无最近 24 小时的听写记录"
    copyButton.isEnabled = selected != nil; deleteButton.isEnabled = selected != nil
  }
  func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let entry = entries[row]
    let status = entry.state == "cancelled" ? "已取消" : entry.state == "completed" ? "已完成" : "识别记录"
    let label = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "time" ? "\(dateFormatter.string(from: entry.startedAt))\n\(status)" : entry.text.replacingOccurrences(of: "\n", with: " "))
    label.maximumNumberOfLines = 2; label.lineBreakMode = .byTruncatingTail; return label
  }
  func tableViewSelectionDidChange(_ notification: Notification) { displaySelection() }
  @objc private func copyText() {
    guard let selected else { return }; writeClipboard(selected.text)
  }
  @objc private func deleteEntry() { if let selected { store.delete(id: selected.id) } }
  @objc private func clearEntries() { store.clear() }
}
