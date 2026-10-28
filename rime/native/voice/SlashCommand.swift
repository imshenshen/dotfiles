import Foundation

public enum RimeSlashCommand: String, CaseIterable, Sendable {
  case symbols
  case gif

  var title: String { self == .symbols ? "符号" : "GIF" }
  var queryPlaceholder: String {
    self == .symbols ? "输入拼音、英文或 Unicode 名称筛选符号" : "输入英文关键词搜索 GIF"
  }
  var footerHint: String {
    self == .symbols ? "↑↓←→ 选择 · Enter 插入 · Tab 分类 · Esc 关闭"
                     : "↑↓←→ 选择 · Enter 复制 GIF · Esc 关闭"
  }
}

enum SlashCommandMatch {
  static func match(input: String, asciiMode: Bool) -> RimeSlashCommand? {
    guard !asciiMode else { return nil }
    switch input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "/fh": return .symbols
    case "/gif": return .gif
    default: return nil
    }
  }
}

struct SlashPaletteState: Equatable {
  var kind: RimeSlashCommand
  var query = ""
  var category: String? = nil
  var selection = 0
  var columns = 6
  var pageRows = 5
  var itemCount = 0

  init(kind: RimeSlashCommand) { self.kind = kind }

  var pageSize: Int { max(1, columns * pageRows) }

  var pageStart: Int {
    guard itemCount > 0 else { return 0 }
    return (min(max(0, selection), itemCount - 1) / pageSize) * pageSize
  }

  var pageNumber: Int { pageStart / pageSize + 1 }
  var pageCount: Int { max(1, (itemCount + pageSize - 1) / pageSize) }

  mutating func setItemCount(_ count: Int) {
    itemCount = max(0, count)
    clampSelection()
  }

  mutating func setColumns(_ value: Int) {
    columns = max(1, value)
    clampSelection()
  }

  @discardableResult
  mutating func append(_ value: String) -> Bool {
    guard value.count == 1, let scalar = value.unicodeScalars.first,
          (32...126).contains(scalar.value), query.count < 120 else { return false }
    query += value
    selection = 0
    return true
  }

  // Returns true when the palette should close.
  mutating func backspace() -> Bool {
    guard !query.isEmpty else { return true }
    query.removeLast()
    selection = 0
    return false
  }

  // Returns true when the palette should close. Escape clears a non-empty
  // query first, then closes; the literal /fh or /gif is never inserted.
  mutating func escape() -> Bool {
    guard query.isEmpty else {
      query = ""
      selection = 0
      return false
    }
    return true
  }

  mutating func move(dx: Int, dy: Int) {
    guard itemCount > 0 else { return }
    if dx != 0 { selection += dx }
    if dy != 0 { selection += dy * columns }
    clampSelection()
  }

  mutating func page(up: Bool) {
    guard itemCount > 0 else { return }
    selection += (up ? -1 : 1) * pageSize
    clampSelection()
  }

  mutating func selectCategory(_ value: String?) {
    category = value == "全部" ? nil : value
    selection = 0
  }

  mutating func cycleCategory(_ categories: [String], backwards: Bool) {
    guard !categories.isEmpty else { return }
    let current = category ?? "全部"
    let index = categories.firstIndex(of: current) ?? 0
    let next = (index + (backwards ? -1 : 1) + categories.count) % categories.count
    selectCategory(categories[next])
  }

  var selectedIndex: Int? {
    guard itemCount > 0, selection >= 0, selection < itemCount else { return nil }
    return selection
  }

  mutating func clampSelection() {
    guard itemCount > 0 else { selection = 0; return }
    selection = min(max(0, selection), itemCount - 1)
  }
}
