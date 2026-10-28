import Foundation

@main struct LiveTest {
  @MainActor static func main() async throws {
    guard let ak = ProcessInfo.processInfo.environment["RIME_SYNC_AK"],
          let sk = ProcessInfo.processInfo.environment["RIME_SYNC_SK"] else {
      print("SKIP: RIME_SYNC_AK/RIME_SYNC_SK not set"); return
    }
    let prefix = "shurufa/rime-sync-live-\(UUID().uuidString)"
    let config = try OSSConfiguration(endpoint: "https://ss-storage-private.oss-cn-beijing.aliyuncs.com",
                                      bucket: "ss-storage-private", prefix: prefix,
                                      accessKeyID: ak, accessKeySecret: sk)
    let client = OSSSyncClient(configuration: config)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("rime-sync-live-\(UUID().uuidString)")
    let a = root.appendingPathComponent("a"), b = root.appendingPathComponent("b")
    let sa = root.appendingPathComponent("sa"), sb = root.appendingPathComponent("sb")
    for d in [a, b, sa, sb] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
    func write(_ dir: URL, _ text: String) throws {
      try Data(text.utf8).write(to: dir.appendingPathComponent("custom_phrase.txt"), options: .atomic)
    }
    do {
      try write(a, "甲\tjia\t100\n")
      try write(b, "乙\tyi\t100\n")
      _ = try await RimeSyncRunner.synchronize(rimeDirectory: a, supportDirectory: sa,
        configuration: config, client: client, syncUserDB: false, rimeSync: nil)
      _ = try await RimeSyncRunner.synchronize(rimeDirectory: b, supportDirectory: sb,
        configuration: config, client: client, syncUserDB: false, rimeSync: nil)
      let bText = try String(contentsOf: b.appendingPathComponent("custom_phrase.txt"), encoding: .utf8)
      precondition(bText.contains("甲") && bText.contains("乙"))
      _ = try await RimeSyncRunner.synchronize(rimeDirectory: a, supportDirectory: sa,
        configuration: config, client: client, syncUserDB: false, rimeSync: nil)
      let aText = try String(contentsOf: a.appendingPathComponent("custom_phrase.txt"), encoding: .utf8)
      precondition(aText.contains("甲") && aText.contains("乙"))
      let remote = try await client.get(config.documentPath)
      precondition(remote != nil)
      let encrypted = remote!.data
      precondition(encrypted.range(of: Data("甲".utf8)) == nil)
      try await client.testConnection()
      print("PASS: live Aliyun OSS encrypted two-machine sync under", prefix)
    }
    try? await client.delete(config.documentPath)
    try? FileManager.default.removeItem(at: root)
  }
}
