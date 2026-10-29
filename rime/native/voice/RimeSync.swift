import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum RimeSyncError: LocalizedError {
  case configuration
  case missingCredentials
  case http(Int)
  case conflict
  case locked
  case invalidDocument
  case decryption
  case fileChanged
  case tooLarge
  case cancelled

  var errorDescription: String? {
    switch self {
    case .configuration: return "词库同步配置无效，请检查 endpoint、bucket、prefix 和凭证。"
    case .missingCredentials: return "尚未配置 OSS 凭证。"
    case .http(let code):
      return code == 0 ? "网络连接失败或超时。" : "词库同步请求失败（HTTP \(code)）。"
    case .conflict: return "远端词库刚被其他电脑更新，请重试同步。"
    case .locked: return "另一台电脑正在同步词库，请稍后重试。"
    case .invalidDocument: return "远端同步数据格式无效。"
    case .decryption: return "无法解密远端词库；如果更换过 OSS 凭证，请重新初始化同步。"
    case .fileChanged: return "本地词库在同步过程中被修改，已保留本地内容，请重试。"
    case .tooLarge: return "词库同步数据超过大小限制。"
    case .cancelled: return "词库同步已取消。"
    }
  }
}

@MainActor
enum RimeSyncSettings {
  static let defaults = UserDefaults(suiteName: "im.rime.inputmethod.Squirrel.RimeSync")!
  static let defaultEndpoint = "https://ss-storage-private.oss-cn-beijing.aliyuncs.com"
  static let defaultBucket = "ss-storage-private"
  static let defaultPrefix = "shurufa/rime-sync/v1"

  static var endpoint: String {
    get { defaults.string(forKey: "endpoint") ?? defaultEndpoint }
    set { defaults.set(newValue, forKey: "endpoint") }
  }
  static var bucket: String {
    get { defaults.string(forKey: "bucket") ?? defaultBucket }
    set { defaults.set(newValue, forKey: "bucket") }
  }
  static var prefix: String {
    get { defaults.string(forKey: "prefix") ?? defaultPrefix }
    set { defaults.set(newValue, forKey: "prefix") }
  }
  static var autoSync: Bool {
    get { defaults.object(forKey: "autoSync") == nil ? true : defaults.bool(forKey: "autoSync") }
    set { defaults.set(newValue, forKey: "autoSync") }
  }
  static var syncUserDB: Bool {
    get { defaults.object(forKey: "syncUserDB") == nil ? true : defaults.bool(forKey: "syncUserDB") }
    set { defaults.set(newValue, forKey: "syncUserDB") }
  }
  static var isConfigured: Bool { RimeSyncCredentials.current() != nil }
}

@MainActor
enum RimeSyncCredentials {
  static let service = "im.rime.inputmethod.Squirrel.RimeSync"
  private static var readStatus: OSStatus = errSecItemNotFound

  enum CredentialError: LocalizedError {
    case storage(OSStatus)
    case readBack(OSStatus)

    var errorDescription: String? {
      switch self {
      case .storage(let status): return "钥匙串保存失败（\(status)），请完成系统认证后重试。"
      case .readBack(let status): return "凭证已写入，但当前鼠须管无法读取（\(status)）。请完成钥匙串认证后再次保存。"
      }
    }
  }

  private static func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }

  static func read(_ account: String) -> String? {
    readStatus = errSecInteractionNotAllowed
    var previousInteraction = DarwinBoolean(true)
    guard SecKeychainGetUserInteractionAllowed(&previousInteraction) == errSecSuccess,
          SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { return nil }
    defer { _ = SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
    var request = query(account)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext(); context.interactionNotAllowed = true
    request[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    readStatus = status
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  static func save(_ value: String, account: String) throws {
    let request = query(account), data = Data(value.utf8)
    var access: SecAccess?
    let accessStatus = SecAccessCreate("鼠须管词库同步" as CFString, nil, &access)
    guard accessStatus == errSecSuccess, let access else {
      throw CredentialError.storage(accessStatus)
    }
    let attributes: [String: Any] = [kSecValueData as String: data,
                                     kSecAttrAccess as String: access]
    let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var addition = request
      addition[kSecValueData as String] = data
      addition[kSecAttrAccess as String] = access
      let added = SecItemAdd(addition as CFDictionary, nil)
      guard added == errSecSuccess else { throw CredentialError.storage(added) }
    } else if status != errSecSuccess {
      throw CredentialError.storage(status)
    }
    guard read(account) == value else {
      throw CredentialError.readBack(readStatus)
    }
  }

  static func remove(_ account: String) throws {
    let status = SecItemDelete(query(account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw CredentialError.storage(status)
    }
  }

  static func current() -> (accessKeyID: String, accessKeySecret: String)? {
    guard let id = read("accessKeyID"), let secret = read("accessKeySecret"),
          !id.isEmpty, !secret.isEmpty else { return nil }
    return (id, secret)
  }
}

struct OSSConfiguration: Sendable {
  let endpoint: URL
  let bucket: String
  let prefix: String
  let accessKeyID: String
  let accessKeySecret: String

  init(endpoint: String, bucket: String, prefix: String, accessKeyID: String,
       accessKeySecret: String) throws {
    let endpointText = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let bucketText = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
    var prefixText = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    while prefixText.contains("//") { prefixText = prefixText.replacingOccurrences(of: "//", with: "/") }
    guard let url = URL(string: endpointText), url.scheme?.lowercased() == "https",
          let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
          url.path.isEmpty || url.path == "/",
          !bucketText.isEmpty,
          !prefixText.isEmpty,
          prefixText == "shurufa" || prefixText.hasPrefix("shurufa/"),
          !prefixText.split(separator: "/").contains(".."),
          prefixText.unicodeScalars.allSatisfy({ (0x21...0x7e).contains($0.value) }),
          !accessKeyID.isEmpty, !accessKeySecret.isEmpty else {
      throw RimeSyncError.configuration
    }
    self.endpoint = url
    self.bucket = bucketText
    self.prefix = prefixText
    self.accessKeyID = accessKeyID
    self.accessKeySecret = accessKeySecret
  }

  var documentPath: String { prefix + "/dictionary.enc" }

  func testPath() -> String { prefix + "/_connection-test.bin" }
}

struct OSSObject: Sendable {
  let data: Data
  let etag: String?
}

private final class OSSNoRedirect: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }
}

private struct OSSLockRecord: Codable, Sendable {
  var schema = 1
  var owner: String
  var token: String
  var state: String
  var updatedAt: Double

  func reclaimable(at now: Double) -> Bool {
    state == "released" || now - updatedAt > 120
  }

  static func decode(_ data: Data) -> OSSLockRecord? {
    if let record = try? JSONDecoder().decode(OSSLockRecord.self, from: data) {
      return record
    }
    // Read locks left by the first shipped build, which used plain text.
    let lines = String(data: data, encoding: .utf8)?.components(separatedBy: "\n") ?? []
    guard lines.count >= 2, let stamp = lines.last.flatMap(Double.init) else { return nil }
    return OSSLockRecord(owner: lines[0], token: "", state: "owned", updatedAt: stamp)
  }
}

struct OSSSyncClient: Sendable {
  let configuration: OSSConfiguration
  let session: URLSession
  private let now: @Sendable () -> Date
  private let lockToken: String

  init(configuration: OSSConfiguration, session: URLSession? = nil,
       lockToken: String = UUID().uuidString,
       now: @escaping @Sendable () -> Date = { Date() }) {
    self.configuration = configuration
    self.lockToken = lockToken
    self.now = now
    if let session { self.session = session }
    else {
      let config = URLSessionConfiguration.ephemeral
      config.timeoutIntervalForRequest = 20
      config.timeoutIntervalForResource = 40
      config.urlCache = nil
      config.httpCookieStorage = nil
      config.urlCredentialStorage = nil
      self.session = URLSession(configuration: config, delegate: OSSNoRedirect(), delegateQueue: nil)
    }
  }

  static func httpDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.string(from: date)
  }

  static func signature(method: String, contentType: String, date: String, path: String,
                        bucket: String, secret: String, ossHeaders: [String: String] = [:]) -> String {
    let canonicalHeaders = ossHeaders
      .filter { $0.key.lowercased().hasPrefix("x-oss-") }
      .map { ($0.key.lowercased(), $0.value) }
      .sorted { $0.0 < $1.0 }
      .map { "\($0.0):\($0.1)\n" }
      .joined()
    let canonical = "\(method)\n\n\(contentType)\n\(date)\n\(canonicalHeaders)/\(bucket)/\(path)"
    let digest = HMAC<Insecure.SHA1>.authenticationCode(for: Data(canonical.utf8),
                                                using: SymmetricKey(data: Data(secret.utf8)))
    return Data(digest).base64EncodedString()
  }

  private func request(method: String, path: String, body: Data?, contentType: String,
                       ossHeaders: [String: String] = [:]) -> URLRequest? {
    let base = configuration.endpoint.absoluteString
    guard let url = URL(string: base + "/" + path) else { return nil }
    let date = Self.httpDate(now())
    let signature = Self.signature(method: method, contentType: contentType, date: date, path: path,
                                   bucket: configuration.bucket, secret: configuration.accessKeySecret,
                                   ossHeaders: ossHeaders)
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.httpMethod = method
    for (name, value) in ossHeaders { request.setValue(value, forHTTPHeaderField: name) }
    request.setValue(date, forHTTPHeaderField: "Date")
    request.setValue("OSS \(configuration.accessKeyID):\(signature)", forHTTPHeaderField: "Authorization")
    if !contentType.isEmpty { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
    request.httpBody = body
    return request
  }

  func get(_ path: String) async throws -> OSSObject? {
    guard let request = request(method: "GET", path: path, body: nil, contentType: "") else {
      throw RimeSyncError.configuration
    }
    let data: Data
    let response: URLResponse
    do { (data, response) = try await session.data(for: request) }
    catch { if Task.isCancelled { throw RimeSyncError.cancelled }; throw RimeSyncError.http(0) }
    guard let http = response as? HTTPURLResponse else { throw RimeSyncError.http(0) }
    if http.statusCode == 404 { return nil }
    guard (200..<300).contains(http.statusCode) else { throw RimeSyncError.http(http.statusCode) }
    guard data.count <= 16 * 1024 * 1024 else { throw RimeSyncError.tooLarge }
    return OSSObject(data: data, etag: http.value(forHTTPHeaderField: "ETag"))
  }

  @discardableResult
  func put(_ data: Data, path: String, forbidOverwrite: Bool = false) async throws -> String? {
    guard data.count <= 16 * 1024 * 1024 else { throw RimeSyncError.tooLarge }
    let headers = forbidOverwrite ? ["x-oss-forbid-overwrite": "true"] : [:]
    guard let request = request(method: "PUT", path: path, body: data,
                                contentType: "application/octet-stream", ossHeaders: headers) else {
      throw RimeSyncError.configuration
    }
    let response: URLResponse
    do { (_, response) = try await session.data(for: request) }
    catch { if Task.isCancelled { throw RimeSyncError.cancelled }; throw RimeSyncError.http(0) }
    guard let http = response as? HTTPURLResponse else { throw RimeSyncError.http(0) }
    if http.statusCode == 409 { throw RimeSyncError.locked }
    guard (200..<300).contains(http.statusCode) else { throw RimeSyncError.http(http.statusCode) }
    return http.value(forHTTPHeaderField: "ETag")
  }

  func delete(_ path: String) async throws {
    guard let request = request(method: "DELETE", path: path, body: nil, contentType: "") else {
      throw RimeSyncError.configuration
    }
    let response: URLResponse
    do { (_, response) = try await session.data(for: request) }
    catch { if Task.isCancelled { throw RimeSyncError.cancelled }; throw RimeSyncError.http(0) }
    guard let http = response as? HTTPURLResponse else { throw RimeSyncError.http(0) }
    guard (200..<300).contains(http.statusCode) || http.statusCode == 404 else {
      throw RimeSyncError.http(http.statusCode)
    }
  }

  private var lockPath: String { configuration.prefix + "/sync.lock" }

  private func lockData(state: String, owner: String) throws -> Data {
    try JSONEncoder().encode(OSSLockRecord(owner: owner, token: lockToken,
                                           state: state, updatedAt: now().timeIntervalSince1970))
  }

  func acquireLock(owner: String) async throws {
    let data = try lockData(state: "owned", owner: owner)
    do {
      _ = try await put(data, path: lockPath, forbidOverwrite: true)
      return
    } catch RimeSyncError.locked {
      // A crashed process can leave a lock behind. Only reclaim it after
      // two minutes; malformed locks are left alone. OSS rejects conditional
      // PUTs, so reclaiming is an overwrite followed by a read-back check.
      // The read-back narrows the race to two clients reclaiming at once.
      guard let object = try? await get(lockPath),
            let existing = OSSLockRecord.decode(object.data),
            existing.reclaimable(at: now().timeIntervalSince1970) else {
        throw RimeSyncError.locked
      }
      do {
        _ = try await put(data, path: lockPath)
      } catch {
        throw RimeSyncError.locked
      }
      guard let confirmed = try? await get(lockPath),
            let current = OSSLockRecord.decode(confirmed.data),
            current.token == lockToken, current.state == "owned" else {
        throw RimeSyncError.locked
      }
    }
  }

  func releaseLock() async {
    // Some networks stall DELETE requests. Publish a released marker with a
    // normal overwrite instead; acquireLock treats it as immediately reusable.
    guard let object = try? await get(lockPath),
          let existing = OSSLockRecord.decode(object.data),
          existing.token == lockToken, existing.state == "owned",
          let released = try? lockData(state: "released", owner: existing.owner) else {
      return
    }
    _ = try? await put(released, path: lockPath)
  }

  func testConnection() async throws {
    // Keep a single probe object instead of delete-after-write. DELETE is
    // blocked or extremely slow on some networks, while GET/PUT are enough to
    // verify the prefix and credentials needed by normal synchronization.
    let path = configuration.testPath()
    let data = Data("rime-sync-probe".utf8)
    _ = try await put(data, path: path)
    guard let object = try? await get(path), object.data == data else {
      throw RimeSyncError.http(0)
    }
  }
}

enum RimeSyncCrypto {
  private static let magic = Data("RSYNC1\n".utf8)

  static func key(secret: String) -> SymmetricKey {
    HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: Data(secret.utf8)),
                           salt: Data("rime-sync-v1".utf8),
                           info: Data("dictionary".utf8),
                           outputByteCount: 32)
  }

  static func seal(_ data: Data, secret: String) throws -> Data {
    do {
      let sealed = try AES.GCM.seal(data, using: key(secret: secret))
      guard let combined = sealed.combined else { throw RimeSyncError.decryption }
      return magic + combined
    } catch let error as RimeSyncError { throw error }
    catch { throw RimeSyncError.decryption }
  }

  static func open(_ data: Data, secret: String) throws -> Data {
    guard data.starts(with: magic) else { throw RimeSyncError.decryption }
    let combined = data.dropFirst(magic.count)
    do {
      let box = try AES.GCM.SealedBox(combined: combined)
      return try AES.GCM.open(box, using: key(secret: secret))
    } catch { throw RimeSyncError.decryption }
  }
}
