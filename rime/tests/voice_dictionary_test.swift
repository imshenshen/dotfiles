import AppKit
import InputMethodKit
enum VoiceSettings { static let mixedSpacing = true }
enum RimeVoiceUI {}
@main struct DictionaryTest {
  @MainActor static func main() throws {
    precondition(KeyboardSpacingDiagnostics.kind("中") == "han")
    precondition(KeyboardSpacingDiagnostics.kind("m") == "latin")
    precondition(KeyboardSpacingDiagnostics.kind(" ") == "space")
    precondition(KeyboardSpacingDiagnostics.kind("。") == "other")
    precondition(KeyboardSpacingDiagnostics.kind(nil) == "none")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-dictionary-test-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("linked.txt"), phrase = root.appendingPathComponent("custom_phrase.txt")
    let text = "# keep comment\nAI助手\taizs\t20\nMac 电脑\tmac\n言犀  yanxi\nnot-a-row\n"
    try Data(text.utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: phrase, withDestinationURL: target)
    let store = VoiceDictionaryStore(directory: root); store.load()
    precondition(store.entries.count == 3)
    precondition(store.selectedHotwords.isEmpty)
    var rows = store.entries; rows[0].doubaoHotword = true; rows[0].spoken = "人工智能助手"
    rows.append(.init(output: "API客户端", code: "api", weight: "100", spoken: "接口客户端"))
    rows.append(.init(output: "Voice Only", code: "", weight: "", spoken: "语音专用"))
    try store.save(rows)
    let destination = try FileManager.default.destinationOfSymbolicLink(atPath: phrase.path)
    precondition(destination == target.path)
    let saved = try String(contentsOf: target, encoding: .utf8)
    precondition(saved.contains("# keep comment") && saved.contains("not-a-row"))
    precondition(saved.contains("Mac 电脑\tmac") && saved.contains("API客户端\tapi\t100"))
    let restored = VoiceDictionaryStore(directory: root); restored.load()
    precondition(restored.entries == rows)
    precondition(restored.selectedHotwords == ["AI助手"])
    var optOut = rows; optOut[0].doubaoHotword = false
    try restored.save(optOut); precondition(restored.selectedHotwords.isEmpty)
    try restored.save(rows)
    precondition(restored.formatter.format("人工智能助手和接口客户端", voice: true) == "AI助手和 API客户端")
    try Data((saved + "# external update\n").utf8).write(to: target)
    do { try store.save(rows); preconditionFailure("must reject concurrent edits") } catch VoiceDictionaryStore.Failure.changed {}
    let importRoot = root.appendingPathComponent("import")
    let importStore = VoiceDictionaryStore(directory: importRoot); importStore.load()
    var imported = VoiceDictionaryEntry(output: "松鼠桥接乙", code: "songshuqiaojieyi", weight: "1", spoken: "", doubaoHotword: false, doubaoImportID: "fixture-id")
    try importStore.save([imported]); importStore.load(force: true)
    precondition(importStore.entries[0].doubaoImportID == "fixture-id")
    imported.output = "我的固定输出"; imported.code = "mycode"
    try importStore.save([imported]); importStore.load(force: true)
    precondition(importStore.entries[0].output == "我的固定输出" && importStore.excludedDoubaoIDs.isEmpty)
    try importStore.save([])
    let deletedStore = VoiceDictionaryStore(directory: importRoot); deletedStore.load(force: true)
    precondition(deletedStore.entries.isEmpty && deletedStore.excludedDoubaoIDs == ["fixture-id"])
    try deletedStore.save([]); deletedStore.load(force: true)
    precondition(deletedStore.entries.isEmpty && deletedStore.excludedDoubaoIDs == ["fixture-id"])
    print("PASS: imported provenance, local edits retained, deletion exclusion survives reload/save")
    print("PASS: shared dictionary round-trip, exact mixed term formatting, aliases, symlink retained, unknown lines retained, concurrent edit protection")
  }
}
