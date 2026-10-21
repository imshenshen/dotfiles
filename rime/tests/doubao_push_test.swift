import Foundation

@main
struct DoubaoPushTest {
  static func main() throws {
    let longWord = String(repeating: "\u{20000}", count: 33)
    let entries: [VoiceDictionaryEntry] = [
      .init(output: "测试A", code: "ceshia", weight: "1", spoken: ""),
      .init(output: "京me", code: "jingme", weight: "", spoken: ""),
      .init(output: "test@example.com", code: "test", weight: "", spoken: ""),
      .init(output: "测试\n", code: "ceshi", weight: "", spoken: ""),
      .init(output: "测试", code: "", weight: "", spoken: ""),
      .init(output: longWord, code: "test", weight: "", spoken: ""),
      .init(output: "重复", code: "ceshi", weight: "", spoken: ""),
      .init(output: "重复", code: "ceshi", weight: "", spoken: ""),
    ]
    let candidates = DoubaoPushPlan.candidates(from: entries)
    precondition(candidates.count == 4, "unexpected candidates: \(candidates)")
    precondition(candidates.map(\.output) == ["测试A", "京me", "test@example.com", "重复"])
    precondition(candidates.map(\.index) == [0, 1, 2, 3])
    let tsv = DoubaoPushPlan.inputTSV(candidates)
    precondition(tsv == "测试A\tceshia\t1\n京me\tjingme\t\ntest@example.com\ttest\t\n重复\tceshi\t\n", "unexpected TSV \(tsv)")

    let preview = """
    engine noise
    P\t0\t测试A\tceshia\tce shi a\tcanonical\tok
    P\t1\t京me\tjingme\tjing me\tcanonical\texists
    P\t2\t重复\tceshi\tce shi\tcode\tok
    """
    let rows = DoubaoPushPlan.parsePreview(preview)
    precondition(rows.count == 3, "unexpected preview rows: \(rows)")
    precondition(rows[0].statusText == "可添加")
    precondition(rows[0].sourceText == "规范拼音")
    precondition(rows[1].selectable == false)
    precondition(rows[2].sourceText == "编码分段")

    let apply = "A\tadded=2\texists=1\tskipped=0\tfailed=0\tbackup=/tmp/a b\n"
    let result = DoubaoPushPlan.parseApply(apply)
    precondition(result == .init(added: 2, exists: 1, skipped: 0, failed: 0, backup: "/tmp/a b"))

    let failure = DoubaoPushPlan.helperError(from: "noise\nE\tengine_mismatch\tengine changed\n")
    precondition(failure?.name == "engine_mismatch")
    let localized = DoubaoPushPlan.localizedError(name: failure!.name, message: failure!.message)
    precondition(localized.contains("重新运行"), "unexpected error \(localized)")

    let running = DoubaoPushPlan.helperError(from: "E\tdoubao_running\tquit\n")
    precondition(DoubaoPushPlan.localizedError(name: running!.name, message: running!.message).contains("仍在运行"))

    if DoubaoPushPlan.helperInstalled {
      let version = try DoubaoDictionaryPush.defaultRunner(.version, "")
      precondition(version.status == 0, "helper version failed: \(version.stderr)")
      precondition(version.stdout.contains("engine_ok=1"), "unexpected helper version: \(version.stdout)")
      let preview = try DoubaoDictionaryPush.defaultRunner(.preview, "测试A\tceshia\n")
      precondition(preview.status == 0, "helper preview failed: \(preview.stderr)")
      let previewRows = DoubaoPushPlan.parsePreview(preview.stdout)
      precondition(previewRows.count == 1, "unexpected helper preview: \(preview.stdout)")
      precondition(previewRows[0].status == "ok" || previewRows[0].status == "exists")
    }

    print("PASS: doubao push plan")
  }
}
