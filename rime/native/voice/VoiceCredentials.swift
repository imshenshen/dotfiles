import Foundation
import Security
import LocalAuthentication

@MainActor enum VoiceCredentials {
  private static let service = "im.rime.inputmethod.Squirrel.DoubaoSpeech"
  private static var readStatus: [String: OSStatus] = [:]
  private static func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }
  static func read(_ account: String) -> String? {
    readStatus[account] = errSecInteractionNotAllowed
    // Legacy login-keychain ACLs can ignore LAContext.interactionNotAllowed.
    // Serialize this short, read-only query and restore its previous UI policy.
    var previousInteraction = DarwinBoolean(true)
    guard SecKeychainGetUserInteractionAllowed(&previousInteraction) == errSecSuccess, SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { return nil }
    defer { _ = SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
    var request = query(account)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext(); context.interactionNotAllowed = true
    request[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    readStatus[account] = status
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
  static func save(_ value: String, account: String) throws {
    let request = query(account), data = Data(value.utf8)
    // Updating the secret alone preserves the old build's trusted-application
    // ACL. Refresh it only when the user explicitly saves a credential.
    var access: SecAccess?
    let accessStatus = SecAccessCreate("鼠须管豆包语音" as CFString, nil, &access)
    guard accessStatus == errSecSuccess, let access else { throw CredentialError.storage(accessStatus) }
    let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccess as String: access]
    let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var addition = request
      addition[kSecValueData as String] = data
      addition[kSecAttrAccess as String] = access
      // macOS login-keychain ACLs control access; iOS accessibility attributes are unsupported here.
      let added = SecItemAdd(addition as CFDictionary, nil)
      guard added == errSecSuccess else { throw CredentialError.storage(added) }
    } else if status != errSecSuccess { throw CredentialError.storage(status) }
    // Never report a successful save when this running build cannot read it.
    guard read(account) == value else { throw CredentialError.readBack(readStatus[account] ?? errSecInteractionNotAllowed) }
  }
  static func clear() {
    for account in ["apiKey", "accessToken"] { _ = SecItemDelete(query(account) as CFDictionary) }
  }
  enum CredentialError: LocalizedError {
    case storage(OSStatus), readBack(OSStatus)
    var errorDescription: String? {
      switch self {
      case .storage(let status): return "钥匙串保存失败（\(status)），请完成系统认证后重试。"
      case .readBack(let status): return "凭证已写入，但当前鼠须管无法读取（\(status)）。请完成钥匙串认证后再次保存。"
      }
    }
  }
}
