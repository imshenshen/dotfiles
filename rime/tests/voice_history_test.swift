import Foundation

@main struct VoiceHistoryTest {
  @MainActor static func main() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("private/history.json")
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    let history = VoiceHistoryStore(url: url, now: { date })
    let started = date
    history.update(id: "one", startedAt: started, text: "", state: "recording")
    precondition(history.entries.isEmpty && !FileManager.default.fileExists(atPath: url.path))
    history.update(id: "one", startedAt: started, text: "第一", state: "recording")
    history.update(id: "one", startedAt: started, text: "第一段🙂最终修订", state: "recording")
    history.update(id: "one", startedAt: started, text: "第一段🙂最终修订", state: "cancelled")
    precondition(history.entries.count == 1 && history.entries[0].state == "cancelled")
    precondition(history.entries[0].text == "第一段🙂最终修订")
    let recovered = VoiceHistoryStore(url: url, now: { date })
    precondition(recovered.entries == history.entries && !recovered.saveFailed)
    let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! NSNumber
    precondition(permissions.intValue == 0o600)
    let parentPermissions = try FileManager.default.attributesOfItem(atPath: url.deletingLastPathComponent().path)[.posixPermissions] as! NSNumber
    precondition(parentPermissions.intValue == 0o700)
    date.addTimeInterval(60)
    history.update(id: "two", startedAt: date, text: "第二次完成", state: "completed")
    precondition(history.entries.map(\.id) == ["two", "one"])
    date = started.addingTimeInterval(VoiceHistoryStore.retention)
    history.cleanup()
    precondition(history.entries.map(\.id) == ["two"])
    precondition(VoiceHistoryStore(url: url, now: { date }).entries.map(\.id) == ["two"])
    date.addTimeInterval(60)
    precondition(VoiceHistoryStore(url: url, now: { date }).entries.isEmpty)
    history.delete(id: "two"); precondition(history.entries.isEmpty)
    history.update(id: "three", startedAt: date, text: "待清空", state: "completed")
    history.clear(); precondition(VoiceHistoryStore(url: url, now: { date }).entries.isEmpty)
    print("PASS: partial/final revision upserts, cancelled-text recovery, relaunch, Unicode, private permissions, 24-hour disk expiry, delete and clear")
  }
}
