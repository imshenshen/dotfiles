import Foundation
import Darwin

import CryptoKit

struct DoubaoDictionaryWord: Equatable {
  let output: String
  let code: String
  let platforms: Int
  var id: String { Self.identifier(output: output, code: code) }
  static func identifier(output: String, code: String) -> String {
    SHA256.hash(data: Data((code + "\t" + output).utf8)).map { String(format: "%02x", $0) }.joined()
  }
}

struct DoubaoDictionaryMerge {
  let additions: [VoiceDictionaryEntry]
  let retained: Int
  let suppressed: Int
  static func plan(local: [VoiceDictionaryEntry], incoming: [DoubaoDictionaryWord], excluding: Set<String>) -> Self {
    func normalized(_ text: String) -> String {
      text.filter { !$0.isWhitespace }.lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
    let manualCodes = Set(local.filter { $0.doubaoImportID == nil && !$0.code.isEmpty }.map(\.code))
    var outputs = Set(local.map { normalized($0.output) })
    var origins = Set(local.compactMap(\.doubaoImportID))
    var additions: [VoiceDictionaryEntry] = []; var retained = 0; var suppressed = 0
    for word in incoming {
      if excluding.contains(word.id) { suppressed += 1; continue }
      if manualCodes.contains(word.code) || origins.contains(word.id) || outputs.contains(normalized(word.output)) { retained += 1; continue }
      outputs.insert(normalized(word.output)); origins.insert(word.id)
      additions.append(.init(output: word.output, code: word.code, weight: "1", spoken: "", doubaoHotword: false, doubaoImportID: word.id))
    }
    return .init(additions: additions, retained: retained, suppressed: suppressed)
  }
}

// Read-only implementation of the observed side-dictionary format. No vendor
// executable is loaded, no credentials are accessed, and no network calls occur.
enum DoubaoDictionaryReader {
  struct Snapshot {
    let words: [DoubaoDictionaryWord]
    let records: Int
    let skipped: Int
    let fingerprint: String
  }
  enum Failure: LocalizedError {
    case missing, multipleAccounts, changing, unsupported, invalid
    var errorDescription: String? {
      switch self {
      case .missing: return "没有找到 Mac 豆包已下载的词库。请先在豆包登录并开启个人词库同步，完成一次中文选词后再试。"
      case .multipleAccounts: return "发现多个豆包账号词库，暂不能安全确定当前账号；本次未合并。"
      case .changing: return "豆包词库正在更新，请稍后重新读取。"
      case .unsupported: return "此豆包词库格式尚未支持；本次未合并，请更新兼容适配后再试。"
      case .invalid: return "豆包词库不完整或校验失败；本次未合并。"
      }
    }
  }
  private struct Bytes {
    let value: [UInt8]
    func int(_ offset: Int, _ size: Int) throws -> Int {
      guard offset >= 0, size > 0, offset <= value.count - size else { throw Failure.invalid }
      return (0..<size).reduce(0) { $0 | Int(value[offset + $1]) << ($1 * 8) }
    }
    func slice(_ start: Int, _ length: Int) throws -> Data {
      guard start >= 0, length >= 0, start <= value.count - length else { throw Failure.invalid }
      return Data(value[start..<(start + length)])
    }
  }
  static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> Snapshot {
    let fm = FileManager.default
    let root = home.resolvingSymlinksInPath().appendingPathComponent("Library/Application Support/DoubaoIme/EngineUserDictAccounts", isDirectory: true)
    guard (try? root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw Failure.invalid }
    let children = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])) ?? []
    let files = children.filter {
      let info = try? $0.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      return info?.isDirectory == true && info?.isSymbolicLink != true && fm.fileExists(atPath: $0.appendingPathComponent("usr_side_dict.dat").path)
    }.map { $0.appendingPathComponent("usr_side_dict.dat") }
    guard !files.isEmpty else { throw Failure.missing }
    guard files.count == 1 else { throw Failure.multipleAccounts }
    let file = files[0]
    guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw Failure.invalid }
    func read() throws -> Data {
      let fd = open(file.path, O_RDONLY | O_NOFOLLOW)
      guard fd >= 0 else { throw Failure.invalid }
      let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
      var stat = Darwin.stat()
      guard fstat(fd, &stat) == 0, stat.st_mode & S_IFMT == S_IFREG,
            stat.st_size >= 48, stat.st_size <= 16 * 1024 * 1024 else { throw Failure.invalid }
      return try handle.read(upToCount: 16 * 1024 * 1024 + 1) ?? Data()
    }
    for _ in 0..<3 {
      let data = try read()
      if data == (try read()) { return try decode(data) }
    }
    throw Failure.changing
  }
  static func decode(_ data: Data) throws -> Snapshot {
    guard data.count >= 48, data.count <= 16 * 1024 * 1024 else { throw Failure.invalid }
    let b = Bytes(value: Array(data))
    let h = try (0..<12).map { try b.int($0 * 4, 4) }
    guard h[0] == 12044, h[1] == 20260710, h[2] == 48 else { throw Failure.unsupported }
    guard h[3] == data.count, h[4] >= 2, h[4] <= 250_000, h[5] == 48,
          h[6] == h[4] * 10, h[7] <= 100_000, h[8] == h[5] + h[6],
          h[10] == h[8] + h[9], h[10] + h[11] == data.count else { throw Failure.invalid }
    // Extension schema 7, item schema 4, attribute schema 4 (14 bytes).
    let ext = h[10]
    guard h[11] == 51, try b.int(ext, 2) == 49,
          try b.int(ext + 2, 1) == 7, try b.int(ext + 3, 1) == 4,
          try b.int(ext + 4, 1) == 4, try b.int(ext + 5, 2) == 14 else { throw Failure.unsupported }
    struct Node { let label: Int; let child: Int; let value: Int }
    let nodes = try (0..<h[4]).map { i in
      let o = h[5] + i * 10
      return try Node(label: b.int(o, 2), child: b.int(o + 2, 4), value: b.int(o + 6, 4))
    }
    let sentinel = nodes.count - 1
    guard nodes[0].label == 0, nodes[0].child == 1, nodes[0].value == 0,
          nodes[sentinel].child == sentinel, nodes[sentinel].value == h[9] else { throw Failure.invalid }
    // Adjacent nodes delimit child and value ranges; validate the entire tree,
    // including empty nodes, before exposing any imported rows.
    var stack = [(0, 0)], visited = Set<Int>()
    while let (i, depth) = stack.popLast() {
      guard i < sentinel, depth <= 64, visited.insert(i).inserted else { throw Failure.invalid }
      let a = nodes[i], z = nodes[i + 1]
      guard a.child <= z.child, z.child <= sentinel, a.value <= z.value, z.value <= h[9] else { throw Failure.invalid }
      for child in a.child..<z.child {
        guard child > i else { throw Failure.invalid }
        stack.append((child, depth + 1))
      }
    }
    guard visited.count == sentinel else { throw Failure.invalid }
    let codePattern = try NSRegularExpression(pattern: "^[a-z][a-z0-9']*( [a-z0-9']+)*$")
    var words: [DoubaoDictionaryWord] = [], records = 0, skipped = 0, keyCount = 0
    for i in 0..<sentinel {
      let a = nodes[i].value, z = nodes[i + 1].value
      if a == z { continue }
      keyCount += 1
      let end = h[8] + z; var cursor = h[8] + a
      let count = try b.int(cursor, 4); cursor += 4
      guard count > 0, count <= 100_000 - records else { throw Failure.invalid }
      for _ in 0..<count {
        let length = try b.int(cursor, 2); cursor += 2
        let itemEnd = cursor + length
        guard itemEnd <= end, length >= 7 else { throw Failure.invalid }
        let wordLength = try b.int(cursor, 2); cursor += 2
        guard wordLength > 0, wordLength % 2 == 0, cursor + wordLength + 2 <= itemEnd,
              let output = String(data: try b.slice(cursor, wordLength), encoding: .utf16LittleEndian) else { throw Failure.invalid }
        cursor += wordLength
        let inputLength = try b.int(cursor, 2); cursor += 2
        guard cursor + inputLength + 3 <= itemEnd,
              let code = String(data: try b.slice(cursor, inputLength), encoding: .utf8) else { throw Failure.invalid }
        cursor += inputLength
        let platforms = try b.int(cursor, 1), attrLength = try b.int(cursor + 1, 2); cursor += 3
        guard platforms >= 1, platforms <= 3, attrLength == platforms.nonzeroBitCount * 14,
              cursor + attrLength == itemEnd else { throw Failure.invalid }
        var positive = false
        for j in 0..<platforms.nonzeroBitCount {
          let frequency = try b.int(cursor + j * 14, 4); positive = positive || frequency > 0
        }
        cursor = itemEnd; records += 1
        let codeRange = NSRange(code.startIndex..., in: code)
        let validCode = code.utf8.count <= 256 && codePattern.firstMatch(in: code, range: codeRange)?.range == codeRange
        if positive && validCode && output.utf16.count <= 128 && !output.contains(where: { $0.isNewline || $0 == "\t" || $0 == "\0" }) {
          words.append(.init(output: output, code: code, platforms: platforms))
        } else { skipped += 1 }
      }
      guard cursor == end else { throw Failure.invalid }
    }
    guard keyCount == h[7] else { throw Failure.invalid }
    words.sort { $0.output == $1.output ? $0.code < $1.code : $0.output < $1.output }
    return .init(words: words, records: records, skipped: skipped,
      fingerprint: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
  }
}
