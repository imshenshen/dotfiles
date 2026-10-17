import Foundation

struct VoiceHistoryEntry: Codable, Equatable, Identifiable {
  let id: String
  let startedAt: Date
  var updatedAt: Date
  var text: String
  var state: String
}

// Private local data, deliberately outside Rime/dotfiles and release resources.
@MainActor final class VoiceHistoryStore {
  static let shared = VoiceHistoryStore(url: FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/Squirrel/VoiceHistory/history.json"))
  static let changed = Notification.Name("SquirrelVoiceHistoryChanged")
  static let retention: TimeInterval = 24 * 60 * 60
  private let url: URL
  private let now: () -> Date
  private var records: [VoiceHistoryEntry] = []
  private var timer: Timer?
  private(set) var saveFailed = false

  init(url: URL, now: @escaping () -> Date = Date.init) {
    self.url = url; self.now = now
    if let data = try? Data(contentsOf: url) {
      if let saved = try? JSONDecoder().decode([VoiceHistoryEntry].self, from: data) { records = saved }
      else { saveFailed = true }
    }
    cleanup()
  }
  func startCleanup() {
    cleanup()
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.cleanup() }
    }
  }
  var entries: [VoiceHistoryEntry] {
    cleanup()
    return records.sorted { $0.startedAt > $1.startedAt }
  }
  func update(id: String, startedAt: Date, text: String, state: String) {
    cleanup()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let entry = VoiceHistoryEntry(id: id, startedAt: startedAt, updatedAt: now(), text: text, state: state)
    if let index = records.firstIndex(where: { $0.id == id }) { records[index] = entry }
    else { records.append(entry) }
    persist()
  }
  func delete(id: String) { records.removeAll { $0.id == id }; persist() }
  func clear() { records.removeAll(); persist() }
  func cleanup() {
    let cutoff = now().addingTimeInterval(-Self.retention)
    let count = records.count
    records.removeAll { $0.updatedAt <= cutoff }
    if records.count != count { persist() }
  }
  private func persist() {
    do {
      let directory = url.deletingLastPathComponent()
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
      var privateDirectory = directory
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try? privateDirectory.setResourceValues(values)
      try JSONEncoder().encode(records).write(to: url, options: .atomic)
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
      saveFailed = false
    } catch { saveFailed = true }
    NotificationCenter.default.post(name: Self.changed, object: self)
  }
}
