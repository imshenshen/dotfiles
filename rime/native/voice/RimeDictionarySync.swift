import Foundation

struct RimeDictionarySnapshot: Equatable {
  var entries: [VoiceDictionaryEntry]
  var exclusions: [VoiceDictionaryEntry]
  var preserved: [String]
  var phraseModifiedAt: Date
  var metadataModifiedAt: Date
  var phraseData: Data
  var metadataData: Data
}

enum RimeDictionaryFiles {
  static let schemaVersion = 1
  static let maxRecords = 100_000

  static func phraseURL(in directory: URL) -> URL {
    directory.appendingPathComponent("custom_phrase.txt").resolvingSymlinksInPath()
  }
  static func metadataURL(in directory: URL) -> URL {
    directory.appendingPathComponent("mixed_user_dictionary.json")
  }

  static func activeKey(code: String, output: String) -> String {
    "a:" + code + "\t" + output
  }
  static func suppressionKey(_ id: String) -> String {
    "s:" + id
  }

  static func load(in directory: URL) throws -> RimeDictionarySnapshot {
    let phrase = phraseURL(in: directory)
    let metadata = metadataURL(in: directory)
    let phraseData = (try? Data(contentsOf: phrase)) ?? Data()
    let metadataData = (try? Data(contentsOf: metadata)) ?? Data()
    let phraseDate = (try? phrase.resourceValues(forKeys: [.contentModificationDateKey])
      .contentModificationDate) ?? Date(timeIntervalSince1970: 0)
    let metadataDate = (try? metadata.resourceValues(forKeys: [.contentModificationDateKey])
      .contentModificationDate) ?? Date(timeIntervalSince1970: 0)

    let saved: [VoiceDictionaryEntry]
    if metadataData.isEmpty {
      saved = []
    } else {
      do { saved = try JSONDecoder().decode([VoiceDictionaryEntry].self, from: metadataData) }
      catch { throw RimeSyncError.invalidDocument }
    }
    var savedByKey: [String: VoiceDictionaryEntry] = [:]
    for entry in saved where entry.doubaoSuppressed != true {
      let key = entry.code + "\t" + entry.output
      if savedByKey[key] == nil { savedByKey[key] = entry }
    }

    var entries: [VoiceDictionaryEntry] = []
    var preserved: [String] = []
    for line in (String(data: phraseData, encoding: .utf8) ?? "").components(separatedBy: .newlines) {
      if line.isEmpty || line.hasPrefix("#") {
        preserved.append(line)
        continue
      }
      var columns = line.components(separatedBy: "\t")
      if columns.count < 2 {
        columns = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
      }
      guard columns.count >= 2 else {
        preserved.append(line)
        continue
      }
      let output = columns[0], code = columns[1]
      let old = savedByKey[code + "\t" + output]
      entries.append(.init(output: output, code: code,
                           weight: columns.count > 2 ? columns[2] : "",
                           spoken: old?.spoken ?? "",
                           doubaoHotword: old?.doubaoHotword,
                           doubaoImportID: old?.doubaoImportID,
                           doubaoSuppressed: nil))
    }
    entries += saved.filter { $0.code.isEmpty && $0.doubaoSuppressed != true && !$0.output.isEmpty }
    let activeIDs = Set(entries.compactMap(\.doubaoImportID))
    let exclusions = saved.filter { $0.doubaoImportID != nil &&
      ($0.doubaoSuppressed == true || !activeIDs.contains($0.doubaoImportID!)) }
      .map { VoiceDictionaryEntry(output: "", code: "", weight: "", spoken: "",
                                  doubaoHotword: false, doubaoImportID: $0.doubaoImportID,
                                  doubaoSuppressed: true) }
    let snapshot = RimeDictionarySnapshot(entries: entries, exclusions: exclusions,
                                          preserved: preserved,
                                          phraseModifiedAt: phraseDate,
                                          metadataModifiedAt: metadataDate,
                                          phraseData: phraseData,
                                          metadataData: metadataData)
    _ = try records(from: snapshot)
    return snapshot
  }

  static func records(from snapshot: RimeDictionarySnapshot) throws -> [String: RimeSyncRecord] {
    var result: [String: RimeSyncRecord] = [:]
    for entry in snapshot.entries {
      let record = RimeSyncRecord(key: activeKey(code: entry.code, output: entry.output),
                                  output: entry.output, code: entry.code, weight: entry.weight,
                                  spoken: entry.spoken,
                                  hotword: entry.doubaoHotword == true,
                                  importID: entry.doubaoImportID,
                                  suppressed: false, updatedAt: 0, deleted: false)
      try validate(record)
      guard result[record.key] == nil else { throw RimeSyncError.invalidDocument }
      result[record.key] = record
    }
    for entry in snapshot.exclusions {
      guard let id = entry.doubaoImportID else { continue }
      let record = RimeSyncRecord(key: suppressionKey(id), output: "", code: "", weight: "",
                                  spoken: "", hotword: false, importID: id, suppressed: true,
                                  updatedAt: 0, deleted: false)
      try validate(record)
      guard result[record.key] == nil else { throw RimeSyncError.invalidDocument }
      result[record.key] = record
    }
    return result
  }

  static func validate(_ record: RimeSyncRecord) throws {
    guard record.key.count <= 1024, !record.key.contains(where: { $0.isNewline }),
          record.updatedAt.isFinite, record.recordsCountValid else {
      throw RimeSyncError.invalidDocument
    }
    if record.deleted {
      guard record.key.hasPrefix("a:") || record.key.hasPrefix("s:") else {
        throw RimeSyncError.invalidDocument
      }
      return
    }
    if record.suppressed {
      guard record.key.hasPrefix("s:"), let id = record.importID,
            !id.isEmpty, id.count <= 256,
            id.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }),
            !id.contains("/"), !id.contains("\\"),
            record.output.isEmpty, record.code.isEmpty else {
        throw RimeSyncError.invalidDocument
      }
      guard record.key == suppressionKey(id) else { throw RimeSyncError.invalidDocument }
      return
    }
    guard !record.output.isEmpty,
          !record.output.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }),
          record.output.utf16.count <= 1024,
          !record.spoken.contains(where: { $0 == "\t" || $0 == "\n" || $0 == "\r" }),
          record.spoken.utf16.count <= 1024,
          record.code.isEmpty || record.code.range(of: "^[a-z][a-z0-9']*( [a-z0-9']+)*$",
                                                   options: .regularExpression) != nil,
          record.weight.isEmpty || (Int(record.weight).map { $0 >= 0 } ?? false),
          record.key == activeKey(code: record.code, output: record.output) else {
      throw RimeSyncError.invalidDocument
    }
  }

  static func write(records: [RimeSyncRecord], to snapshot: RimeDictionarySnapshot,
                    in directory: URL, backupDirectory: URL?) throws {
    var active: [VoiceDictionaryEntry] = []
    var exclusions: [VoiceDictionaryEntry] = []
    var seen = Set<String>()
    for record in records where !record.deleted {
      try validate(record)
      if record.suppressed {
        guard let id = record.importID else { continue }
        exclusions.append(.init(output: "", code: "", weight: "", spoken: "",
                                doubaoHotword: false, doubaoImportID: id,
                                doubaoSuppressed: true))
      } else {
        guard seen.insert(record.code + "\t" + record.output).inserted else {
          throw RimeSyncError.invalidDocument
        }
        active.append(.init(output: record.output, code: record.code,
                            weight: record.weight, spoken: record.spoken,
                            doubaoHotword: record.hotword ? true : nil,
                            doubaoImportID: record.importID,
                            doubaoSuppressed: nil))
      }
    }
    let activeIDs = Set(active.compactMap(\.doubaoImportID))
    exclusions.removeAll { entry in
      guard let id = entry.doubaoImportID else { return true }
      return activeIDs.contains(id)
    }
    let phrase = phraseURL(in: directory)
    let metadata = metadataURL(in: directory)
    guard ((try? Data(contentsOf: phrase)) ?? Data()) == snapshot.phraseData,
          ((try? Data(contentsOf: metadata)) ?? Data()) == snapshot.metadataData else {
      throw RimeSyncError.fileChanged
    }

    let body = snapshot.preserved.joined(separator: "\n").trimmingCharacters(in: .newlines) +
      "\n\n" + active.filter { !$0.code.isEmpty }.map {
        $0.output + "\t" + $0.code + ($0.weight.isEmpty ? "" : "\t" + $0.weight)
      }.joined(separator: "\n") + "\n"
    let data = Data(body.utf8)
    let metadataData = try JSONEncoder().encode(active + exclusions)
    if let backupDirectory {
      try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
      let stamp = Int(Date().timeIntervalSince1970)
      if snapshot.phraseData.count > 0 {
        try? snapshot.phraseData.write(to: backupDirectory.appendingPathComponent("custom_phrase-\(stamp).txt"),
                                       options: .atomic)
      }
      if snapshot.metadataData.count > 0 {
        try? snapshot.metadataData.write(to: backupDirectory.appendingPathComponent("mixed_user_dictionary-\(stamp).json"),
                                         options: .atomic)
      }
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try metadataData.write(to: metadata, options: .atomic)
    do {
      try data.write(to: phrase, options: .atomic)
    } catch {
      try? snapshot.metadataData.write(to: metadata, options: .atomic)
      throw error
    }
  }
}

struct RimeSyncRecord: Codable, Equatable, Sendable {
  var key: String
  var output: String
  var code: String
  var weight: String
  var spoken: String
  var hotword: Bool
  var importID: String?
  var suppressed: Bool
  var updatedAt: Double
  var deleted: Bool

  var recordsCountValid: Bool { key.count <= 1024 }

  func sameContent(as other: RimeSyncRecord) -> Bool {
    deleted == other.deleted && suppressed == other.suppressed &&
      output == other.output && code == other.code && weight == other.weight &&
      spoken == other.spoken && hotword == other.hotword && importID == other.importID
  }
}

struct RimeSyncUserDBSnapshot: Codable, Equatable, Sendable {
  var path: String
  var content: String
  var modifiedAt: Double
}

struct RimeSyncDocument: Codable, Equatable, Sendable {
  var schema: Int = RimeDictionaryFiles.schemaVersion
  var deviceID: String
  var updatedAt: Double
  var records: [RimeSyncRecord]
  var userdbSnapshots: [RimeSyncUserDBSnapshot]

  init(deviceID: String, updatedAt: Double, records: [RimeSyncRecord],
       userdbSnapshots: [RimeSyncUserDBSnapshot] = []) {
    self.deviceID = deviceID
    self.updatedAt = updatedAt
    self.records = records
    self.userdbSnapshots = userdbSnapshots
  }
}

struct RimeSyncState: Codable, Equatable {
  var schema: Int = RimeDictionaryFiles.schemaVersion
  var deviceID: String
  var remoteETag: String?
  var lastSyncAt: Double
  var records: [RimeSyncRecord]
}

struct RimeSyncMergeResult {
  var records: [RimeSyncRecord]
  var conflicts: Int
  var localChanged: Bool
}

enum RimeSyncMerge {
  static func merge(local: RimeDictionarySnapshot, state: RimeSyncState,
                    remote: RimeSyncDocument?, now: Date) throws -> RimeSyncMergeResult {
    let localRecords = try RimeDictionaryFiles.records(from: local)
    var base: [String: RimeSyncRecord] = [:]
    for record in state.records {
      try RimeDictionaryFiles.validate(record)
      guard base[record.key] == nil else { throw RimeSyncError.invalidDocument }
      base[record.key] = record
    }
    var remoteMap: [String: RimeSyncRecord] = [:]
    if let remote {
      guard remote.schema == RimeDictionaryFiles.schemaVersion else {
        throw RimeSyncError.invalidDocument
      }
      for record in remote.records {
        try RimeDictionaryFiles.validate(record)
        guard remoteMap[record.key] == nil else { throw RimeSyncError.invalidDocument }
        remoteMap[record.key] = record
      }
    }

    let firstSync = state.lastSyncAt <= 0
    let fileDate = min(max(local.phraseModifiedAt, local.metadataModifiedAt), now)
    let baseline = firstSync && fileDate.timeIntervalSince1970 > 0 ? fileDate : now
    var localMap: [String: RimeSyncRecord] = [:]
    for (key, var record) in localRecords {
      let old = base[key]
      if let old, !old.deleted, old.sameContent(as: record) {
        record.updatedAt = old.updatedAt
      } else if let old, old.deleted, old.sameContent(as: record) {
        record.updatedAt = old.updatedAt
      } else {
        record.updatedAt = baseline.timeIntervalSince1970
      }
      localMap[key] = record
    }
    for (key, old) in base {
      if localRecords[key] != nil { continue }
      if old.deleted { localMap[key] = old; continue }
      localMap[key] = RimeSyncRecord(key: key, output: "", code: "", weight: "", spoken: "",
                                     hotword: false, importID: nil, suppressed: false,
                                     updatedAt: now.timeIntervalSince1970, deleted: true)
    }

    var merged: [String: RimeSyncRecord] = [:]
    var conflicts = 0
    let keys = Set(localMap.keys).union(remoteMap.keys).union(base.keys)
    for key in keys {
      let localRecord = localMap[key]
      let remoteRecord = remoteMap[key]
      let baseRecord = base[key]
      let localChanged: Bool
      if let localRecord {
        if let baseRecord { localChanged = !baseRecord.sameContent(as: localRecord) }
        else { localChanged = true }
      } else {
        localChanged = baseRecord.map { !$0.deleted } ?? false
      }
      let remoteChanged: Bool
      if let remoteRecord {
        if let baseRecord { remoteChanged = !baseRecord.sameContent(as: remoteRecord) }
        else { remoteChanged = true }
      } else {
        remoteChanged = false
      }

      let chosen: RimeSyncRecord?
      if let localRecord, let remoteRecord {
        let winner = localRecord.updatedAt >= remoteRecord.updatedAt ? localRecord : remoteRecord
        if localRecord.sameContent(as: remoteRecord) {
          chosen = winner
        } else if let baseRecord, !baseRecord.deleted, !localRecord.deleted, !remoteRecord.deleted,
                  !localRecord.suppressed, !remoteRecord.suppressed {
          if localChanged && remoteChanged { conflicts += 1 }
          chosen = mergeFields(local: localRecord, remote: remoteRecord, base: baseRecord, winner: winner)
        } else {
          if localChanged && remoteChanged { conflicts += 1 }
          chosen = winner
        }
      } else if let localRecord {
        chosen = localRecord
      } else if let remoteRecord {
        chosen = remoteRecord
      } else {
        chosen = baseRecord
      }
      if let chosen { merged[key] = chosen }
    }

    let records = merged.values.sorted { $0.key < $1.key }
    guard records.count <= RimeDictionaryFiles.maxRecords else { throw RimeSyncError.tooLarge }
    let localAfter = try RimeDictionaryFiles.records(from: local)
    let localChanged = records.filter { !$0.deleted }.reduce(into: [String: RimeSyncRecord]()) {
      $0[$1.key] = $1
    } != localAfter
    return RimeSyncMergeResult(records: records, conflicts: conflicts, localChanged: localChanged)
  }

  private static func mergeFields(local: RimeSyncRecord, remote: RimeSyncRecord,
                                  base: RimeSyncRecord, winner: RimeSyncRecord) -> RimeSyncRecord {
    func choose<T: Equatable>(_ localValue: T, _ remoteValue: T, _ baseValue: T) -> T {
      let localChanged = localValue != baseValue
      let remoteChanged = remoteValue != baseValue
      if localChanged && !remoteChanged { return localValue }
      if remoteChanged && !localChanged { return remoteValue }
      return winner == local ? localValue : remoteValue
    }
    var result = winner
    result.output = choose(local.output, remote.output, base.output)
    result.code = choose(local.code, remote.code, base.code)
    result.weight = choose(local.weight, remote.weight, base.weight)
    result.spoken = choose(local.spoken, remote.spoken, base.spoken)
    result.hotword = choose(local.hotword, remote.hotword, base.hotword)
    result.importID = choose(local.importID, remote.importID, base.importID)
    result.suppressed = false
    result.deleted = false
    result.updatedAt = max(local.updatedAt, remote.updatedAt)
    return result
  }
}

enum RimeSyncUserDB {
  static let maxFiles = 10_000
  static let maxTotalBytes = 8 * 1024 * 1024
  private static let installationPattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]+$")
  private static let filePattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9._-]+\\.userdb\\.txt$")

  static func validPath(_ path: String) -> Bool {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    guard parts.count == 2, parts[0] != ".", parts[0] != "..", parts[1] != ".", parts[1] != "..",
          matches(parts[0], installationPattern), matches(parts[1], filePattern) else { return false }
    return true
  }
  private static func matches(_ value: String, _ pattern: NSRegularExpression) -> Bool {
    pattern.firstMatch(in: value, range: NSRange(location: 0, length: value.utf16.count)) != nil
  }

  static func collect(in rimeDirectory: URL) throws -> [RimeSyncUserDBSnapshot] {
    let sync = rimeDirectory.appendingPathComponent("sync", isDirectory: true)
    guard let directories = try? FileManager.default.contentsOfDirectory(
      at: sync, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
      return []
    }
    var result: [RimeSyncUserDBSnapshot] = []
    var total = 0
    for directory in directories {
      guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
            matches(directory.lastPathComponent, installationPattern) else { continue }
      let files = (try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
        options: [.skipsHiddenFiles])) ?? []
      for file in files where matches(file.lastPathComponent, filePattern) {
        guard result.count < maxFiles else { throw RimeSyncError.tooLarge }
        guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
        let values = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let size = values.fileSize ?? 0
        guard size <= 2 * 1024 * 1024, total + size <= maxTotalBytes else { throw RimeSyncError.tooLarge }
        guard let data = try? Data(contentsOf: file),
              let content = String(data: data, encoding: .utf8) else { throw RimeSyncError.invalidDocument }
        total += data.count
        result.append(.init(path: directory.lastPathComponent + "/" + file.lastPathComponent,
                            content: content,
                            modifiedAt: values.contentModificationDate?.timeIntervalSince1970 ?? 0))
      }
    }
    return result.sorted { $0.path < $1.path }
  }

  @discardableResult
  static func apply(_ snapshots: [RimeSyncUserDBSnapshot], to rimeDirectory: URL) throws -> Bool {
    let sync = rimeDirectory.appendingPathComponent("sync", isDirectory: true)
    var changed = false
    for snapshot in snapshots {
      guard validPath(snapshot.path), snapshot.content.utf8.count <= 2 * 1024 * 1024 else {
        throw RimeSyncError.invalidDocument
      }
      let target = sync.appendingPathComponent(snapshot.path)
      let values = try? target.resourceValues(forKeys: [.contentModificationDateKey])
      let localDate = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
      if localDate > snapshot.modifiedAt + 1 { continue }
      if let data = try? Data(contentsOf: target),
         String(data: data, encoding: .utf8) == snapshot.content { continue }
      try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                              withIntermediateDirectories: true,
                                              attributes: [.posixPermissions: 0o700])
      try Data(snapshot.content.utf8).write(to: target, options: .atomic)
      try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
      if snapshot.modifiedAt > 0 {
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: snapshot.modifiedAt)],
                                               ofItemAtPath: target.path)
      }
      changed = true
    }
    return changed
  }

  static func merge(local: [RimeSyncUserDBSnapshot],
                    remote: [RimeSyncUserDBSnapshot]) -> [RimeSyncUserDBSnapshot] {
    var result = Dictionary(uniqueKeysWithValues: local.map { ($0.path, $0) })
    for snapshot in remote {
      guard validPath(snapshot.path) else { continue }
      if let current = result[snapshot.path], current.modifiedAt > snapshot.modifiedAt { continue }
      result[snapshot.path] = snapshot
    }
    return result.values.sorted { $0.path < $1.path }
  }
}
