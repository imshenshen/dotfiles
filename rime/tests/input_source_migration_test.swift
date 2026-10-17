import Foundation

enum SquirrelApp { static let appDir = URL(fileURLWithPath: "/nonexistent/Squirrel.app") }
final class MemoryDefaults: UserDefaults {
  var records: [[String: Any]]
  var writes = 0
  var synchronization = [Bool]()
  init(_ records: [[String: Any]]) { self.records = records; super.init(suiteName: nil)! }
  override func array(forKey defaultName: String) -> [Any]? { records }
  override func set(_ value: Any?, forKey defaultName: String) { records = value as! [[String: Any]]; writes += 1 }
  override func synchronize() -> Bool { synchronization.isEmpty ? true : synchronization.removeFirst() }
}
@main struct InputSourceMigrationTest {
  static func main() throws {
    let id = "im.rime.inputmethod.Squirrel.Hans"
    let legacy = ["Bundle ID":"im.rime.inputmethod.Squirrel", "Input Mode":id, "InputSourceKind":"Input Mode"]
    let abc: [String: Any] = ["InputSourceKind":"Keyboard Layout", "KeyboardLayout Name":"ABC", "KeyboardLayout ID":252]
    let other: [String: Any] = ["Bundle ID":"com.example.other", "Input Mode":"com.example.other.mode", "InputSourceKind":"Input Mode"]
    let original: [[String: Any]] = [abc, legacy, other]
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let backup = directory.appendingPathComponent("private/Legacy.plist")
    for ids in [[], [id], ["im.rime.inputmethod.Squirrel.Hant", id]] {
      let mock = MemoryDefaults(original)
      precondition(!SquirrelInstaller.retireLegacyDuplicate(defaults: mock, enabledModeIDs: ids, backupURL: backup))
      precondition(mock.writes == 0 && !FileManager.default.fileExists(atPath: backup.path))
    }
    let mock = MemoryDefaults(original)
    precondition(SquirrelInstaller.retireLegacyDuplicate(defaults: mock, enabledModeIDs: [id, id], backupURL: backup))
    precondition(mock.records.count == 2 && mock.records[0]["KeyboardLayout ID"] as? Int == 252 && mock.records[1]["Bundle ID"] as? String == "com.example.other")
    let saved = try PropertyListSerialization.propertyList(from: Data(contentsOf: backup), options: [], format: nil) as! [[String: Any]]
    precondition(saved.count == 3 && saved[1]["Input Mode"] as? String == id)
    let attributes = try FileManager.default.attributesOfItem(atPath: backup.path)
    precondition((attributes[.posixPermissions] as! NSNumber).intValue == 0o600)
    precondition(!SquirrelInstaller.retireLegacyDuplicate(defaults: mock, enabledModeIDs: [id,id], backupURL: backup) && mock.writes == 1)
    let ambiguous = MemoryDefaults([legacy, legacy, abc])
    precondition(!SquirrelInstaller.retireLegacyDuplicate(defaults: ambiguous, enabledModeIDs: [id,id], backupURL: backup) && ambiguous.writes == 0)
    var enriched = legacy; enriched["custom"] = "preserve"
    precondition(SquirrelInstaller.sourcesWithoutLegacyDuplicate([enriched], enabledModeIDs: [id,id]) == nil)
    let failed = MemoryDefaults(original); failed.synchronization = [false,true]
    precondition(!SquirrelInstaller.retireLegacyDuplicate(defaults: failed, enabledModeIDs: [id,id], backupURL: backup))
    precondition(failed.records.count == 3 && failed.records[1]["Input Mode"] as? String == id)
    let badDirectory = directory.appendingPathComponent("not-a-directory")
    try Data().write(to: badDirectory)
    let unwritable = MemoryDefaults(original)
    precondition(!SquirrelInstaller.retireLegacyDuplicate(defaults: unwritable, enabledModeIDs: [id,id], backupURL: badDirectory.appendingPathComponent("backup.plist")) && unwritable.writes == 0)
    print("PASS: duplicate-only legacy migration, private backup, sole-source/other-source preservation, idempotence, ambiguous-state refusal and failure rollback")
  }
}
