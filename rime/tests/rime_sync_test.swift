import Foundation

final class RimeSyncStubURLProtocol: URLProtocol {
  static var objects: [String: (data: Data, etag: String)] = [:]
  static var requests: [URLRequest] = []
  static var nextETag = 1

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  private static func body(of request: URLRequest) -> Data? {
    if let data = request.httpBody { return data }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open(); defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count <= 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }

  override func startLoading() {
    Self.requests.append(request)
    let path = request.url?.path ?? ""
    switch request.httpMethod {
    case "GET", "HEAD":
      guard let object = Self.objects[path] else {
        respond(status: 404, data: Data())
        return
      }
      respond(status: 200, data: object.data, etag: object.etag)
    case "PUT":
      if request.value(forHTTPHeaderField: "x-oss-forbid-overwrite") == "true",
         Self.objects[path] != nil {
        respond(status: 409, data: Data()); return
      }
      let data = Self.body(of: request) ?? Data()
      let etag = "\"etag-\(Self.nextETag)\""
      Self.nextETag += 1
      Self.objects[path] = (data, etag)
      respond(status: 200, data: Data(), etag: etag)
    case "DELETE":
      Self.objects.removeValue(forKey: path)
      respond(status: 204, data: Data())
    default:
      respond(status: 405, data: Data())
    }
  }

  private func respond(status: Int, data: Data, etag: String? = nil) {
    var headers = ["Content-Length": "\(data.count)"]
    if let etag { headers["ETag"] = etag }
    let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: "HTTP/1.1", headerFields: headers)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: data)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

@main struct RimeSyncTest {
  static func tempDir(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rime-sync-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  static func makeSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [RimeSyncStubURLProtocol.self]
    return URLSession(configuration: config)
  }

  static func snapshot(entries: [VoiceDictionaryEntry],
                       exclusions: [VoiceDictionaryEntry] = [],
                       date: Date = Date(timeIntervalSince1970: 100),
                       preserved: [String] = ["# kept comment"]) -> RimeDictionarySnapshot {
    RimeDictionarySnapshot(entries: entries, exclusions: exclusions, preserved: preserved,
                           phraseModifiedAt: date, metadataModifiedAt: date,
                           phraseData: Data(), metadataData: Data())
  }

  static func record(_ code: String, _ output: String, spoken: String = "",
                     hotword: Bool = false, importID: String? = nil,
                     updatedAt: Double = 100) -> RimeSyncRecord {
    RimeSyncRecord(key: RimeDictionaryFiles.activeKey(code: code, output: output),
                   output: output, code: code, weight: "", spoken: spoken,
                   hotword: hotword, importID: importID, suppressed: false,
                   updatedAt: updatedAt, deleted: false)
  }

  static func tombstone(_ key: String, at: Double) -> RimeSyncRecord {
    RimeSyncRecord(key: key, output: "", code: "", weight: "", spoken: "",
                   hotword: false, importID: nil, suppressed: false,
                   updatedAt: at, deleted: true)
  }

  static func writeFiles(_ dir: URL, phrase: String, metadata: [VoiceDictionaryEntry] = []) throws {
    try Data(phrase.utf8).write(to: dir.appendingPathComponent("custom_phrase.txt"), options: .atomic)
    if !metadata.isEmpty {
      try JSONEncoder().encode(metadata).write(to: dir.appendingPathComponent("mixed_user_dictionary.json"),
                                               options: .atomic)
    }
  }

  @MainActor static func main() async throws {
    precondition(OSSSyncClient.signature(method: "PUT", contentType: "application/octet-stream",
      date: "Wed, 28 Oct 2026 15:18:45 GMT", path: "shurufa/rime-sync/v1/dictionary.enc",
      bucket: "ss-storage-private", secret: "test-secret") == "vStHefLUUPQq74uc8DySLHCC/ZI=")

    let secret = "sync-secret"
    let key = RimeSyncCrypto.key(secret: secret)
    let sealed = try RimeSyncCrypto.seal(Data("hello".utf8), secret: secret)
    let opened = try RimeSyncCrypto.open(sealed, secret: secret)
    precondition(opened == Data("hello".utf8))
    precondition((try? RimeSyncCrypto.open(sealed, secret: "wrong")) == nil)
    precondition(key.bitCount == 256)

    // File round trip, metadata preservation and comments.
    let files = try tempDir("files")
    let metadata = [VoiceDictionaryEntry(output: "你好", code: "ni hao", weight: "100",
                                         spoken: "你好呀", doubaoHotword: true),
                    VoiceDictionaryEntry(output: "", code: "", weight: "", spoken: "",
                                         doubaoHotword: false, doubaoImportID: "hash", doubaoSuppressed: true)]
    try writeFiles(files, phrase: "# kept comment\n\n你好\tni hao\t100\n", metadata: metadata)
    let loaded = try RimeDictionaryFiles.load(in: files)
    precondition(loaded.entries.count == 1 && loaded.entries[0].spoken == "你好呀")
    precondition(loaded.entries[0].doubaoHotword == true && loaded.exclusions.count == 1)
    precondition(loaded.preserved.contains("# kept comment"))
    let records = try RimeDictionaryFiles.records(from: loaded)
    precondition(records.count == 2)
    var changed = records
    let new = record("test", "测试", spoken: "测试别名", hotword: true, updatedAt: 200)
    changed[new.key] = new
    try RimeDictionaryFiles.write(records: Array(changed.values), to: loaded, in: files, backupDirectory: nil)
    let reloaded = try RimeDictionaryFiles.load(in: files)
    precondition(reloaded.entries.contains { $0.output == "测试" && $0.spoken == "测试别名" &&
      $0.doubaoHotword == true })
    precondition(reloaded.exclusions.count == 1 && reloaded.preserved.contains("# kept comment"))

    // Merge: local edit, remote edit, deletion, tombstone and re-add.
    let baseEntry = record("base", "基础", spoken: "old", updatedAt: 100)
    let baseState = RimeSyncState(deviceID: "A", remoteETag: nil, lastSyncAt: 50, records: [baseEntry])
    let localEdit = snapshot(entries: [VoiceDictionaryEntry(output: "基础", code: "base",
      weight: "", spoken: "new")])
    let localOnly = try RimeSyncMerge.merge(local: localEdit, state: baseState, remote: nil,
                                            now: Date(timeIntervalSince1970: 200))
    precondition(localOnly.records.first { $0.code == "base" }?.spoken == "new")
    precondition(localOnly.records.first { $0.code == "base" }?.updatedAt == 200)

    let localSame = snapshot(entries: [VoiceDictionaryEntry(output: "基础", code: "base",
      weight: "", spoken: "old")])
    let remoteEdit = RimeSyncDocument(deviceID: "B", updatedAt: 150, records: [
      RimeSyncRecord(key: baseEntry.key, output: "基础", code: "base", weight: "", spoken: "remote",
                     hotword: false, importID: nil, suppressed: false, updatedAt: 150, deleted: false)
    ])
    let remoteMerge = try RimeSyncMerge.merge(local: localSame, state: baseState, remote: remoteEdit,
                                              now: Date(timeIntervalSince1970: 200))
    precondition(remoteMerge.records.first { $0.code == "base" }?.spoken == "remote")

    let deletedLocal = snapshot(entries: [])
    let deletedMerge = try RimeSyncMerge.merge(local: deletedLocal, state: baseState, remote: nil,
                                               now: Date(timeIntervalSince1970: 210))
    precondition(deletedMerge.records.first { $0.key == baseEntry.key }?.deleted == true)
    let deletedState = RimeSyncState(deviceID: "A", remoteETag: nil, lastSyncAt: 210,
                                     records: deletedMerge.records)
    let reAdd = snapshot(entries: [VoiceDictionaryEntry(output: "基础", code: "base", weight: "",
      spoken: "")])
    let reAddMerge = try RimeSyncMerge.merge(local: reAdd, state: deletedState, remote: nil,
                                             now: Date(timeIntervalSince1970: 220))
    precondition(reAddMerge.records.first { $0.key == baseEntry.key }?.deleted == false)

    let conflictLocal = snapshot(entries: [VoiceDictionaryEntry(output: "基础", code: "base",
      weight: "", spoken: "local-conflict")])
    let conflictRemote = RimeSyncDocument(deviceID: "B", updatedAt: 160, records: [
      RimeSyncRecord(key: baseEntry.key, output: "基础", code: "base", weight: "", spoken: "old",
                     hotword: true, importID: nil, suppressed: false, updatedAt: 160, deleted: false)
    ])
    let conflict = try RimeSyncMerge.merge(local: conflictLocal, state: baseState,
                                           remote: conflictRemote, now: Date(timeIntervalSince1970: 170))
    precondition(conflict.conflicts == 1)
    precondition(conflict.records.first { $0.code == "base" }?.hotword == true)

    // Suppression records and invalid remote data.
    let suppression = VoiceDictionaryEntry(output: "", code: "", weight: "", spoken: "",
                                           doubaoHotword: false, doubaoImportID: "abc",
                                           doubaoSuppressed: true)
    let suppressionRecords = try RimeDictionaryFiles.records(from: snapshot(entries: [], exclusions: [suppression]))
    precondition(suppressionRecords.values.first?.suppressed == true)
    let invalidRemote = RimeSyncDocument(deviceID: "B", updatedAt: 1, records: [
      RimeSyncRecord(key: "a:\t", output: "", code: "", weight: "", spoken: "",
                     hotword: false, importID: nil, suppressed: false, updatedAt: 1, deleted: false)
    ])
    do {
      _ = try RimeSyncMerge.merge(local: localSame, state: baseState, remote: invalidRemote,
                                  now: Date())
      preconditionFailure("invalid remote record accepted")
    } catch RimeSyncError.invalidDocument {}

    // Userdb snapshot file validation and application.
    let userdbRoot = try tempDir("userdb")
    let sync = userdbRoot.appendingPathComponent("sync/inst-a", isDirectory: true)
    try FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: sync.appendingPathComponent("wubi86.userdb.txt"))
    let collected = try RimeSyncUserDB.collect(in: userdbRoot)
    precondition(collected.count == 1 && collected[0].path == "inst-a/wubi86.userdb.txt")
    let replacement = RimeSyncUserDBSnapshot(path: "inst-a/wubi86.userdb.txt", content: "new",
                                             modifiedAt: Date().timeIntervalSince1970 + 10)
    let applied = try RimeSyncUserDB.apply([replacement], to: userdbRoot)
    precondition(applied)
    let replaced = try String(contentsOf: sync.appendingPathComponent("wubi86.userdb.txt"), encoding: .utf8)
    precondition(replaced == "new")
    do {
      _ = try RimeSyncUserDB.apply([.init(path: "../escape.userdb.txt", content: "x", modifiedAt: 1)],
                                   to: userdbRoot)
      preconditionFailure("path traversal accepted")
    } catch RimeSyncError.invalidDocument {}

    // OSS client conditional requests and in-memory multi-machine sync.
    RimeSyncStubURLProtocol.objects = [:]
    RimeSyncStubURLProtocol.requests = []
    RimeSyncStubURLProtocol.nextETag = 1
    let config = try OSSConfiguration(endpoint: "https://sync.example.test",
      bucket: "ss-storage-private", prefix: "shurufa/rime-sync/v1",
      accessKeyID: "test-ak", accessKeySecret: secret)
    let session = makeSession()
    let client = OSSSyncClient(configuration: config, session: session)
    let object = try await client.get(config.documentPath)
    precondition(object == nil)
    try await client.testConnection()
    let probePath = "/" + config.testPath()
    precondition(RimeSyncStubURLProtocol.objects[probePath]?.data == Data("rime-sync-probe".utf8))
    RimeSyncStubURLProtocol.objects.removeValue(forKey: probePath)

    // Release is a marker overwrite, never DELETE, so a network that stalls
    // DELETE still releases the lock for the next computer.
    let lockA = OSSSyncClient(configuration: config, session: session)
    let lockB = OSSSyncClient(configuration: config, session: session)
    try await lockA.acquireLock(owner: "lock-a")
    do {
      try await lockB.acquireLock(owner: "lock-b")
      preconditionFailure("a held lock was acquired twice")
    } catch RimeSyncError.locked {}
    await lockA.releaseLock()
    try await lockB.acquireLock(owner: "lock-b")
    await lockB.releaseLock()

    let machineA = try tempDir("machine-a")
    let machineB = try tempDir("machine-b")
    let supportA = try tempDir("support-a")
    let supportB = try tempDir("support-b")
    try writeFiles(machineA, phrase: "甲\tjia\t100\n")
    try writeFiles(machineB, phrase: "乙\tyi\t100\n")
    let clientA = OSSSyncClient(configuration: config, session: session)
    let clientB = OSSSyncClient(configuration: config, session: session)
    _ = try await RimeSyncRunner.synchronize(rimeDirectory: machineA, supportDirectory: supportA,
      configuration: config, client: clientA, syncUserDB: false, rimeSync: nil)
    _ = try await RimeSyncRunner.synchronize(rimeDirectory: machineB, supportDirectory: supportB,
      configuration: config, client: clientB, syncUserDB: false, rimeSync: nil)
    let aAfter = try RimeDictionaryFiles.load(in: machineA)
    let bAfter = try RimeDictionaryFiles.load(in: machineB)
    precondition(aAfter.entries.count == 1 && aAfter.entries[0].output == "甲")
    precondition(bAfter.entries.count == 2 && Set(bAfter.entries.map(\.output)) == Set(["甲", "乙"]))
    _ = try await RimeSyncRunner.synchronize(rimeDirectory: machineA, supportDirectory: supportA,
      configuration: config, client: clientA, syncUserDB: false, rimeSync: nil)
    let aFinal = try RimeDictionaryFiles.load(in: machineA)
    precondition(aFinal.entries.count == 2 && Set(aFinal.entries.map(\.output)) == Set(["甲", "乙"]))
    let remoteData = RimeSyncStubURLProtocol.objects.values.first!.data
    precondition(remoteData.range(of: Data("甲".utf8)) == nil)

    // Userdb snapshot carried in the encrypted bundle.
    let userSyncB = machineB.appendingPathComponent("sync/inst-b", isDirectory: true)
    try FileManager.default.createDirectory(at: userSyncB, withIntermediateDirectories: true)
    try Data("snapshot".utf8).write(to: userSyncB.appendingPathComponent("wubi86.userdb.txt"))
    _ = try await RimeSyncRunner.synchronize(rimeDirectory: machineB, supportDirectory: supportB,
      configuration: config, client: clientB, syncUserDB: true, rimeSync: { true })
    _ = try await RimeSyncRunner.synchronize(rimeDirectory: machineA, supportDirectory: supportA,
      configuration: config, client: clientA, syncUserDB: true, rimeSync: { true })
    let downloaded = machineA.appendingPathComponent("sync/inst-b/wubi86.userdb.txt")
    let downloadedText = try String(contentsOf: downloaded, encoding: .utf8)
    precondition(downloadedText == "snapshot")

    precondition(RimeSyncStubURLProtocol.objects["/" + config.prefix + "/sync.lock"]
      .flatMap { String(data: $0.data, encoding: .utf8) }?.contains("\"released\"") == true)
    precondition(RimeSyncStubURLProtocol.requests.allSatisfy { $0.httpMethod != "DELETE" })

    print("PASS: OSS signature/encryption; dictionary roundtrip/comments; merge add/edit/delete/tombstone/re-add/conflict; userdb path validation and encrypted two-machine sync; DELETE-free lock and connection probe")
  }
}
