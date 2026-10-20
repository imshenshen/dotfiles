import Foundation
@main struct DoubaoDictionaryTest {
  static func fixture(output: String = "松鼠桥接乙", code: String = "songshuqiaojieyi", frequency: Int = 1) -> Data {
    func number(_ v: Int, _ n: Int) -> Data { Data((0..<n).map { UInt8(truncatingIfNeeded: v >> (8 * $0)) }) }
    let word = output.data(using: .utf16LittleEndian)!, input = Data(code.utf8)
    var item = number(word.count, 2) + word + number(input.count, 2) + input + Data([2]) + number(14, 2)
    item += number(frequency, 4) + Data(repeating: 0, count: 10)
    let values = number(1, 4) + number(item.count, 2) + item
    var nodes = number(0, 2) + number(1, 4) + number(0, 4)
    nodes += number(10, 2) + number(2, 4) + number(0, 4)
    nodes += number(0, 2) + number(2, 4) + number(values.count, 4)
    let ext = number(49, 2) + Data([7,4,4]) + number(14, 2) + Data(repeating: 0, count: 44)
    let header = [12044,20260710,48,48 + nodes.count + values.count + ext.count,3,48,30,1,78,values.count,78 + values.count,51]
    var result = header.reduce(Data()) { $0 + number($1, 4) }
    result += nodes; result += values; result += ext; return result
  }
  static func fails(_ body: () throws -> Void) { do { try body(); fatalError("must fail") } catch {} }
  static func main() throws {
    let f = fixture(), snapshot = try DoubaoDictionaryReader.decode(f)
    precondition(snapshot.records == 1 && snapshot.skipped == 0 && snapshot.words.first?.output == "松鼠桥接乙")
    let zero = try DoubaoDictionaryReader.decode(fixture(frequency: 0)); precondition(zero.words.isEmpty)
    let invalid = try DoubaoDictionaryReader.decode(fixture(code: "bad\ncode")); precondition(invalid.skipped == 1)
    let trailing = try DoubaoDictionaryReader.decode(fixture(code: "abc\n")); precondition(trailing.skipped == 1)
    for count in [0, 47, f.count - 1] { fails { _ = try DoubaoDictionaryReader.decode(f.prefix(count)) } }
    for index in [0,4,12,16,20,24,28,32,36,40,44,50,54,74,f.count - 49] {
      var broken = f; broken[index] = 255; fails { _ = try DoubaoDictionaryReader.decode(broken) }
    }
    // Reading is local-only, bounded and refuses an ambiguous account or symlink.
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("doubao-reader-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let root = home.appendingPathComponent("Library/Application Support/DoubaoIme/EngineUserDictAccounts")
    let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try f.write(to: a.appendingPathComponent("usr_side_dict.dat"))
    let loaded = try DoubaoDictionaryReader.load(home: home); precondition(loaded.words == snapshot.words)
    try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
    try f.write(to: b.appendingPathComponent("usr_side_dict.dat"))
    fails { _ = try DoubaoDictionaryReader.load(home: home) }
    try FileManager.default.removeItem(at: b)
    let file = a.appendingPathComponent("usr_side_dict.dat")
    try FileManager.default.removeItem(at: file)
    let target = home.appendingPathComponent("target.dat"); try f.write(to: target)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    fails { _ = try DoubaoDictionaryReader.load(home: home) }
    let term = DoubaoDictionaryWord(output: "MacBookPro", code: "macbookpro", platforms: 1)
    let existing = VoiceDictionaryEntry(output: "MacBook Pro", code: "mbp", weight: "100", spoken: "苹果电脑", doubaoHotword: true)
    let plan = DoubaoDictionaryMerge.plan(local: [existing], incoming: [term] + snapshot.words + snapshot.words, excluding: [])
    precondition(plan.additions.count == 1 && plan.retained == 2 && plan.additions[0].doubaoHotword == false)
    precondition(plan.additions[0].doubaoImportID == snapshot.words[0].id)
    let conflict = VoiceDictionaryEntry(output: "已有手工词", code: snapshot.words[0].code, weight: "", spoken: "")
    let conflictPlan = DoubaoDictionaryMerge.plan(local: [conflict], incoming: snapshot.words, excluding: [])
    precondition(conflictPlan.additions.isEmpty && conflictPlan.retained == 1)
    let excluded = DoubaoDictionaryMerge.plan(local: [], incoming: snapshot.words, excluding: [snapshot.words[0].id])
    precondition(excluded.additions.isEmpty && excluded.suppressed == 1)
    var edited = plan.additions[0]; edited.output = "我的固定格式"; edited.code = "abcd"
    precondition(DoubaoDictionaryMerge.plan(local: [edited], incoming: snapshot.words, excluding: []).additions.isEmpty)
    print("PASS: strict side-dictionary decoding, corrupt/future formats rejected, account isolation, symlink refusal, deduplication, local format/code priority, ASR opt-out, local deletion exclusion")
    if CommandLine.arguments.contains("--live-read") {
      let live = try DoubaoDictionaryReader.load()
      print("Live read: records=\(live.records), usable=\(live.words.count), skipped=\(live.skipped), phoneFixture=\(live.words.contains { $0.output == "松鼠桥接甲" }), macFixture=\(live.words.contains { $0.output == "松鼠桥接乙" })")
    }
  }
}
