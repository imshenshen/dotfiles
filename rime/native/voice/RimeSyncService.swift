import AppKit
import Foundation

struct RimeSyncOutcome {
  var remoteETag: String?
  var records: Int
  var conflicts: Int
  var localChanged: Bool
  var userDBFiles: Int
  var userDBError: String?
}

@MainActor
enum RimeSyncRunner {
  static func synchronize(rimeDirectory: URL, supportDirectory: URL,
                          configuration: OSSConfiguration, client: OSSSyncClient,
                          syncUserDB: Bool, rimeSync: (() -> Bool)?,
                          now: Date = Date()) async throws -> RimeSyncOutcome {
    try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: supportDirectory.path)
    let stateURL = supportDirectory.appendingPathComponent("state.json")
    let state: RimeSyncState
    if FileManager.default.fileExists(atPath: stateURL.path) {
      guard let data = try? Data(contentsOf: stateURL),
            let saved = try? JSONDecoder().decode(RimeSyncState.self, from: data),
            saved.schema == RimeDictionaryFiles.schemaVersion else {
        throw RimeSyncError.invalidDocument
      }
      state = saved
    } else {
      state = RimeSyncState(deviceID: UUID().uuidString, remoteETag: nil, lastSyncAt: 0, records: [])
    }
    let local = try RimeDictionaryFiles.load(in: rimeDirectory)
    try await client.acquireLock(owner: state.deviceID)
    do {
      let outcome = try await synchronizedBody(rimeDirectory: rimeDirectory,
        supportDirectory: supportDirectory, configuration: configuration, client: client,
        syncUserDB: syncUserDB, rimeSync: rimeSync, now: now, state: state,
        local: local, stateURL: stateURL)
      await client.releaseLock()
      return outcome
    } catch {
      await client.releaseLock()
      throw error
    }
  }

  private static func synchronizedBody(rimeDirectory: URL, supportDirectory: URL,
                                       configuration: OSSConfiguration, client: OSSSyncClient,
                                       syncUserDB: Bool, rimeSync: (() -> Bool)?,
                                       now: Date, state: RimeSyncState,
                                       local initialLocal: RimeDictionarySnapshot,
                                       stateURL: URL) async throws -> RimeSyncOutcome {
    var local = initialLocal
    let remoteObject = try await client.get(configuration.documentPath)
    var remoteDocument: RimeSyncDocument?
    if let remoteObject {
      let plain = try RimeSyncCrypto.open(remoteObject.data, secret: configuration.accessKeySecret)
      do { remoteDocument = try JSONDecoder().decode(RimeSyncDocument.self, from: plain) }
      catch { throw RimeSyncError.invalidDocument }
    }
    try validate(remoteDocument)

    let merge = try RimeSyncMerge.merge(local: local, state: state, remote: remoteDocument, now: now)
    var userDBError: String?
    var userDBSnapshots: [RimeSyncUserDBSnapshot]
    var userDBChanged = false
    if syncUserDB, let rimeSync {
      let applied = try RimeSyncUserDB.apply(remoteDocument?.userdbSnapshots ?? [], to: rimeDirectory)
      userDBChanged = applied
      let ok = rimeSync()
      if !ok { userDBError = "学习词库同步失败" }
      userDBSnapshots = try RimeSyncUserDB.collect(in: rimeDirectory)
      if userDBSnapshots != (remoteDocument?.userdbSnapshots ?? []) { userDBChanged = true }
    } else {
      userDBSnapshots = remoteDocument?.userdbSnapshots ?? []
    }

    let document = RimeSyncDocument(deviceID: state.deviceID, updatedAt: now.timeIntervalSince1970,
                                    records: merge.records, userdbSnapshots: userDBSnapshots)
    try validate(document)
    let needsPut = remoteDocument == nil || document.records != remoteDocument?.records ||
      document.userdbSnapshots != remoteDocument?.userdbSnapshots || merge.localChanged || userDBChanged
    var etag = remoteObject?.etag
    if needsPut {
      guard ((try? Data(contentsOf: RimeDictionaryFiles.phraseURL(in: rimeDirectory))) ?? Data()) == local.phraseData,
            ((try? Data(contentsOf: RimeDictionaryFiles.metadataURL(in: rimeDirectory))) ?? Data()) == local.metadataData else {
        throw RimeSyncError.fileChanged
      }
      let plain = try JSONEncoder().encode(document)
      let sealed = try RimeSyncCrypto.seal(plain, secret: configuration.accessKeySecret)
      etag = try await client.put(sealed, path: configuration.documentPath)
    }

    let backup = supportDirectory.appendingPathComponent("backups",
      isDirectory: true).appendingPathComponent(String(Int(now.timeIntervalSince1970)))
    if merge.localChanged {
      try RimeDictionaryFiles.write(records: merge.records, to: local, in: rimeDirectory,
                                    backupDirectory: backup)
      local = try RimeDictionaryFiles.load(in: rimeDirectory)
    }
    if merge.conflicts > 0, let remoteObject {
      try? FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
      try? remoteObject.data.write(to: backup.appendingPathComponent("remote.enc"), options: .atomic)
      try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                             ofItemAtPath: backup.appendingPathComponent("remote.enc").path)
    }
    var newState = state
    newState.remoteETag = etag
    newState.lastSyncAt = now.timeIntervalSince1970
    newState.records = merge.records
    let stateData = try JSONEncoder().encode(newState)
    try stateData.write(to: stateURL, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
    return RimeSyncOutcome(remoteETag: etag, records: merge.records.filter { !$0.deleted }.count,
                           conflicts: merge.conflicts, localChanged: merge.localChanged,
                           userDBFiles: userDBSnapshots.count, userDBError: userDBError)
  }

  private static func validate(_ document: RimeSyncDocument?) throws {
    guard let document else { return }
    guard document.schema == RimeDictionaryFiles.schemaVersion,
          document.records.count <= RimeDictionaryFiles.maxRecords,
          document.userdbSnapshots.count <= RimeSyncUserDB.maxFiles else {
      throw RimeSyncError.invalidDocument
    }
    var total = 0
    for snapshot in document.userdbSnapshots {
      guard RimeSyncUserDB.validPath(snapshot.path),
            snapshot.content.utf8.count <= 2 * 1024 * 1024 else {
        throw RimeSyncError.invalidDocument
      }
      total += snapshot.content.utf8.count
      guard total <= RimeSyncUserDB.maxTotalBytes else { throw RimeSyncError.tooLarge }
    }
    var keys = Set<String>()
    for record in document.records {
      try RimeDictionaryFiles.validate(record)
      guard keys.insert(record.key).inserted else { throw RimeSyncError.invalidDocument }
    }
  }
}

@MainActor
final class RimeSyncService: NSObject {
  static let shared = RimeSyncService()
  static let statusChanged = Notification.Name("SquirrelRimeSyncStatusChanged")

  private let rimeDirectory: URL
  private let supportDirectory: URL
  private var rimeSync: (() -> Bool)?
  private var timer: Timer?
  private var dictionaryObservers: [NSObjectProtocol] = []
  private var scheduledTask: Task<Void, Never>?
  private(set) var syncing = false
  private(set) var dictionaryEditing = false
  private(set) var status = "尚未同步"
  private(set) var lastSyncAt: Date?

  init(rimeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Rime"),
       supportDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Squirrel/RimeSync")) {
    self.rimeDirectory = rimeDirectory
    self.supportDirectory = supportDirectory
    super.init()
  }

  func start(rimeSync: @escaping () -> Bool) {
    self.rimeSync = rimeSync
    if dictionaryObservers.isEmpty {
      let center = NotificationCenter.default
      dictionaryObservers.append(center.addObserver(
        forName: .init("SquirrelDictionaryEditingChanged"), object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated {
          self?.setDictionaryEditing((note.object as? Bool) ?? false)
        }
      })
      dictionaryObservers.append(center.addObserver(
        forName: .init("SquirrelDictionaryDidChange"), object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.schedule(after: 3) }
      })
    }
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.schedule(after: 0) }
    }
    if let timer { RunLoop.main.add(timer, forMode: .common) }
    schedule(after: 20)
  }

  func schedule(after delay: TimeInterval = 3) {
    scheduledTask?.cancel()
    guard RimeSyncSettings.autoSync, RimeSyncSettings.isConfigured else { return }
    scheduledTask = Task { @MainActor [weak self] in
      if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
      guard !Task.isCancelled, let self else { return }
      guard !self.dictionaryEditing else { return }
      await self.runSync()
    }
  }

  func syncNow(completion: ((Result<RimeSyncOutcome, Error>) -> Void)? = nil) {
    scheduledTask?.cancel()
    Task { @MainActor [weak self] in
      guard let self else { return }
      if self.dictionaryEditing {
        self.setStatus("请先关闭用户词典窗口再同步")
        completion?(.failure(RimeSyncError.fileChanged))
        return
      }
      let result = await self.runSync()
      completion?(result)
    }
  }

  @discardableResult
  private func runSync() async -> Result<RimeSyncOutcome, Error> {
    guard !syncing else { return .failure(RimeSyncError.conflict) }
    guard let credentials = RimeSyncCredentials.current() else {
      setStatus("尚未配置 OSS 凭证")
      return .failure(RimeSyncError.missingCredentials)
    }
    let configuration: OSSConfiguration
    do {
      configuration = try OSSConfiguration(endpoint: RimeSyncSettings.endpoint,
                                           bucket: RimeSyncSettings.bucket,
                                           prefix: RimeSyncSettings.prefix,
                                           accessKeyID: credentials.accessKeyID,
                                           accessKeySecret: credentials.accessKeySecret)
    } catch {
      setStatus(error.localizedDescription)
      return .failure(error)
    }
    syncing = true
    setStatus("正在同步…")
    let task = Task { @MainActor [weak self] in
      guard let self else { throw RimeSyncError.cancelled }
      let client = OSSSyncClient(configuration: configuration)
      return try await RimeSyncRunner.synchronize(
        rimeDirectory: self.rimeDirectory, supportDirectory: self.supportDirectory,
        configuration: configuration, client: client,
        syncUserDB: RimeSyncSettings.syncUserDB, rimeSync: self.rimeSync)
    }
    do {
      let outcome = try await task.value
      syncing = false
      lastSyncAt = Date()
      if outcome.localChanged {
        DistributedNotificationCenter.default().postNotificationName(
          .init("SquirrelReloadNotification"), object: nil, userInfo: nil, deliverImmediately: true)
      }
      if let error = outcome.userDBError {
        setStatus("词典已同步；\(error)")
      } else {
        setStatus("已同步 · \(outcome.records) 条词典 · \(outcome.userDBFiles) 个学习快照")
      }
      return .success(outcome)
    } catch {
      syncing = false
      setStatus(error.localizedDescription)
      return .failure(error)
    }
  }

  func setDictionaryEditing(_ value: Bool) {
    dictionaryEditing = value
    if !value { schedule(after: 2) }
  }

  private func setStatus(_ value: String) {
    status = value
    NotificationCenter.default.post(name: Self.statusChanged, object: self)
  }
}

