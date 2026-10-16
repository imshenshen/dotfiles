import AppKit
import InputMethodKit
import Carbon

@MainActor final class VoiceDictionaryStore {
  static let shared = VoiceDictionaryStore()
  private let directory: URL
  private(set) var entries: [VoiceDictionaryEntry] = []
  private var original = Data()
  private var originalMetadata = Data()
  private var preserved: [String] = []
  private var stamp: Date?
  init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Rime")) { self.directory = directory }
  private var phraseFile: URL { directory.appendingPathComponent("custom_phrase.txt").resolvingSymlinksInPath() }
  private var metadataFile: URL { directory.appendingPathComponent("mixed_user_dictionary.json") }
  func load(force: Bool = false) {
    let date = try? phraseFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    if !force, stamp == date, !entries.isEmpty { return }
    stamp = date; original = (try? Data(contentsOf: phraseFile)) ?? Data()
    originalMetadata = (try? Data(contentsOf: metadataFile)) ?? Data()
    let metadata = (try? JSONDecoder().decode([VoiceDictionaryEntry].self, from: originalMetadata)) ?? []
    entries = []; preserved = []
    for line in (String(data: original, encoding: .utf8) ?? "").components(separatedBy: .newlines) {
      if line.isEmpty || line.hasPrefix("#") { preserved.append(line); continue }
      var columns = line.components(separatedBy: "\t")
      if columns.count < 2 { columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init) }
      guard columns.count >= 2 else { preserved.append(line); continue }
      let output = columns[0], code = columns[1]
      let saved = metadata.first { $0.output == output && $0.code == code }
      entries.append(.init(output: output, code: code, weight: columns.count > 2 ? columns[2] : "", spoken: saved?.spoken ?? "", doubaoHotword: saved?.doubaoHotword))
    }
    entries += metadata.filter { $0.code.isEmpty }
  }
  func save(_ values: [VoiceDictionaryEntry]) throws {
    guard ((try? Data(contentsOf: phraseFile)) ?? Data()) == original,
          ((try? Data(contentsOf: metadataFile)) ?? Data()) == originalMetadata else { throw Failure.changed }
    guard Set(values.filter { $0.doubaoHotword == true }.map(\.output)).count <= 5000 else { throw Failure.hotwordLimit }
    var seen = Set<String>()
    for entry in values {
      guard !entry.output.isEmpty, !entry.output.contains(where: { "\t\n\r".contains($0) }),
            !entry.spoken.contains(where: { "\t\n\r".contains($0) }),
            entry.code.isEmpty || entry.code.range(of: "^[a-z][a-z0-9']*( [a-z0-9']+)*$", options: .regularExpression) != nil,
            entry.weight.isEmpty || (Int(entry.weight).map { $0 >= 0 } ?? false) else { throw Failure.invalid }
      guard seen.insert(entry.code + "\t" + entry.output).inserted else { throw Failure.duplicate }
    }
    let body = preserved.joined(separator: "\n").trimmingCharacters(in: .newlines) + "\n\n" + values.filter { !$0.code.isEmpty }.map {
      $0.output + "\t" + $0.code + ($0.weight.isEmpty ? "" : "\t" + $0.weight)
    }.joined(separator: "\n") + "\n"
    let data = Data(body.utf8), metadata = try JSONEncoder().encode(values)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if !original.isEmpty { try original.write(to: phraseFile.appendingPathExtension("backup-\(Int(Date().timeIntervalSince1970))"), options: .atomic) }
    try metadata.write(to: metadataFile, options: .atomic)
    do { try data.write(to: phraseFile, options: .atomic) }
    catch {
      try? originalMetadata.write(to: metadataFile, options: .atomic); throw error
    }
    original = data; originalMetadata = metadata; entries = values; stamp = nil
  }
  var selectedHotwords: [String] {
    load(force: true); var seen = Set<String>()
    return Array(entries.filter { $0.doubaoHotword == true && !$0.output.isEmpty }
      .map(\.output).filter { seen.insert($0).inserted }.prefix(5000))
  }
  var formatter: VoiceTextFormatter {
    load(); return VoiceTextFormatter(spaces: VoiceSettings.mixedSpacing, entries: entries)
  }
  enum Failure: LocalizedError {
    case changed, invalid, duplicate, hotwordLimit
    var errorDescription: String? {
      switch self {
      case .hotwordLimit: return "最多勾选 5000 个不同的豆包热词，请减少勾选。"
      case .changed: return "词典已被其他程序修改，请关闭页面重新打开后编辑。"
      case .invalid: return "输出不能为空，不能含换行或 Tab；编码使用小写字母、数字和单引号，权重为非负整数。"
      case .duplicate: return "同一输出和编码重复，请合并后保存。"
      }
    }
  }
}

extension RimeVoiceUI {
  @MainActor public static func formatCommittedText(_ text: String, client: IMKTextInput) -> String {
    let marked = client.markedRange(), selected = client.selectedRange()
    let range = marked.location != NSNotFound && marked.length > 0 ? marked : selected
    var before = "", after = ""; var previousAtStart = false
    if range.location != NSNotFound {
      if range.location > 0 {
        let length = min(32, range.location)
        previousAtStart = length == range.location
        before = client.attributedSubstring(from: NSRange(location: range.location-length, length: length))?.string ?? ""
      }
      after = client.attributedSubstring(from: NSRange(location: NSMaxRange(range), length: 2))?.string ?? ""
    }
    return VoiceDictionaryStore.shared.formatter.format(text, previous: before, following: after, previousAtStart: previousAtStart)
  }
}

@MainActor final class VoiceDictionaryPreferences: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
  static let shared = VoiceDictionaryPreferences()
  private var window: NSWindow?
  private let table = NSTableView()
  private let message = NSTextField(labelWithString: "")
  private var rows: [VoiceDictionaryEntry] = []
  func show() {
    if window == nil { create() }
    VoiceDictionaryStore.shared.load(force: true); rows = VoiceDictionaryStore.shared.entries; table.reloadData()
    message.stringValue = "Tab 向右，别名栏继续 Tab 新增下一条。仅勾选的词随下次豆包录音发送；不上传编码、权重和别名。"
    window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
  }
  private func create() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.title = "用户词典 · 五笔、拼音与语音"; window.isReleasedWhenClosed = false; window.delegate = self
    window.center(); self.window = window
    let root = window.contentView!
    let scroll = NSScrollView(frame: NSRect(x: 20, y: 100, width: 820, height: 350))
    scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
    for (id, title, width) in [("output", "固定输出（格式原样保留）", 245.0), ("code", "输入编码", 150.0), ("weight", "权重", 60.0), ("spoken", "语音识别别名（可选）", 235.0)] {
      let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width; column.isEditable = true; table.addTableColumn(column)
    }
    let hotword = NSTableColumn(identifier: .init("hotword")); hotword.title = "豆包热词"; hotword.width = 90
    let checkbox = NSButtonCell(); checkbox.setButtonType(.switch); checkbox.title = ""; hotword.dataCell = checkbox
    hotword.isEditable = true; table.addTableColumn(hotword)
    table.dataSource = self; table.delegate = self; table.rowHeight = 28; table.usesAlternatingRowBackgroundColors = true
    scroll.documentView = table; root.addSubview(scroll)
    message.frame = NSRect(x: 20, y: 53, width: 820, height: 36); message.autoresizingMask = [.width]
    message.font = .systemFont(ofSize: 11); message.maximumNumberOfLines = 2; root.addSubview(message)
    for (title, action, x) in [("添加", #selector(add), 20.0), ("删除所选", #selector(remove), 115.0), ("保存并部署", #selector(save), 700.0)] {
      let button = NSButton(title: title, target: self, action: action); button.bezelStyle = .rounded
      button.frame = NSRect(x: x, y: 14, width: x == 20 ? 90 : x == 115 ? 120 : 140, height: 32); if x == 700 { button.autoresizingMask = [.minXMargin] }; root.addSubview(button)
    }
  }
  func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
  func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
    switch tableColumn?.identifier.rawValue {
    case "output": return rows[row].output; case "code": return rows[row].code
    case "weight": return rows[row].weight; case "hotword": return rows[row].doubaoHotword == true
    default: return rows[row].spoken
    }
  }
  func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
    let value = object as? String ?? ""
    switch tableColumn?.identifier.rawValue {
    case "output": rows[row].output = value; case "code": rows[row].code = value
    case "weight": rows[row].weight = value; case "hotword": rows[row].doubaoHotword = (object as? NSNumber)?.boolValue ?? false
    default: rows[row].spoken = value
    }
  }
  func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
    let backward = commandSelector == #selector(NSResponder.insertBacktab(_:))
    guard backward || commandSelector == #selector(NSResponder.insertTab(_:)),
          table.editedRow >= 0, table.editedColumn >= 0 else { return false }
    let row = table.editedRow, column = table.editedColumn
    guard window?.makeFirstResponder(nil) == true else { return true }
    var nextRow = row, nextColumn = column + (backward ? -1 : 1)
    if nextColumn < 0 { nextRow = max(0, row-1); nextColumn = row > 0 ? 3 : 0 }
    if nextColumn > 3 {
      nextRow += 1; nextColumn = 0
      if nextRow == rows.count {
        if rows[row].output.isEmpty { nextRow = row }
        else { rows.append(.init(output: "", code: "", weight: "", spoken: "")); table.reloadData() }
      }
    }
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.table.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
      self.table.scrollRowToVisible(nextRow)
      self.table.editColumn(nextColumn, row: nextRow, with: nil, select: true)
    }
    return true
  }
  @objc private func add() {
    rows.append(.init(output: "", code: "", weight: "", spoken: "")); table.reloadData()
    table.selectRowIndexes(IndexSet(integer: rows.count-1), byExtendingSelection: false); table.editColumn(0, row: rows.count-1, with: nil, select: true)
  }
  @objc private func remove() {
    window?.makeFirstResponder(nil)
    for index in table.selectedRowIndexes.reversed() { rows.remove(at: index) }; table.reloadData()
  }
  @objc private func save() {
    guard window?.makeFirstResponder(nil) == true else { return }
    do {
      try VoiceDictionaryStore.shared.save(rows.filter { !$0.output.isEmpty || !$0.code.isEmpty || !$0.weight.isEmpty || !$0.spoken.isEmpty })
      DistributedNotificationCenter.default().postNotificationName(.init("SquirrelReloadNotification"), object: nil, userInfo: nil, deliverImmediately: true)
      message.stringValue = "已保存；五笔、拼音重新部署后生效。语音词条在下次录音生效。"
    } catch { message.stringValue = error.localizedDescription }
  }
}

// One instance per input controller: spacing ownership must not cross clients.
@MainActor public final class RimeDirectTextInput {
  private var spacing = DirectTextSpacing()
  public init() {}
  public func reset() { spacing.reset() }
  public func handle(_ event: NSEvent, client: IMKTextInput, enabled: Bool) -> Bool {
    // Shift changes alone do not interrupt a word (e.g. camelCase).
    if event.type == .flagsChanged { return false }
    guard enabled, VoiceSettings.mixedSpacing, !IsSecureEventInputEnabled(), event.type == .keyDown,
          event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty,
          let text = event.characters,
          client.markedRange().location == NSNotFound || client.markedRange().length == 0 else { reset(); return false }
    let selected = client.selectedRange()
    guard selected.location != NSNotFound, selected.length == 0 else { reset(); return false }
    let length = min(32, selected.location)
    let before = client.attributedSubstring(from: NSRange(location: selected.location-length, length: length))?.string ?? ""
    let after = client.attributedSubstring(from: NSRange(location: selected.location, length: 2))?.string ?? ""
    guard let insertion = spacing.insertion(text, at: selected, previous: before, following: after,
                                           formatter: VoiceDictionaryStore.shared.formatter) else { return false }
    let replacement = insertion.range.length == 0 ? NSRange(location: NSNotFound, length: 0) : insertion.range
    client.insertText(insertion.text, replacementRange: replacement)
    return true
  }
}
