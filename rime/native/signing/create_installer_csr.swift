import Foundation
import Security

// The private key is generated permanently in the login keychain and is never exported.
@main struct InstallerCSR {
  static func der(_ tag: UInt8, _ value: Data) -> Data {
    var length = value.count
    var encoded = Data()
    if length < 128 { encoded.append(UInt8(length)) }
    else {
      var bytes: [UInt8] = []
      while length > 0 { bytes.insert(UInt8(length & 255), at: 0); length >>= 8 }
      encoded.append(0x80 | UInt8(bytes.count)); encoded.append(contentsOf: bytes)
    }
    return Data([tag]) + encoded + value
  }
  static func main() throws {
    guard CommandLine.arguments.count == 3 else { fatalError("Usage: create-installer-csr KEY_TAG PUBLIC_CSR_PATH") }
    let tag = Data(CommandLine.arguments[1].utf8), output = URL(fileURLWithPath: CommandLine.arguments[2])
    let query: [String: Any] = [kSecClass as String: kSecClassKey, kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
      kSecAttrKeyClass as String: kSecAttrKeyClassPrivate, kSecAttrApplicationTag as String: tag, kSecReturnRef as String: true]
    var found: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &found)
    let key: SecKey
    if status == errSecSuccess { key = found as! SecKey }
    else if status == errSecItemNotFound {
      let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048,
        kSecPrivateKeyAttrs as String: [kSecAttrIsPermanent as String: true, kSecAttrApplicationTag as String: tag,
          kSecAttrLabel as String: "Squirrel Developer ID Installer"]]
      var error: Unmanaged<CFError>?
      guard let created = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else { throw error!.takeRetainedValue() }
      key = created
    } else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    var error: Unmanaged<CFError>?
    guard let publicKey = SecKeyCopyPublicKey(key), let publicDER = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { throw error!.takeRetainedValue() }
    let rsa = der(0x30, der(0x06,Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x01])) + der(0x05,Data()))
    let commonName = der(0x30,der(0x31,der(0x30,der(0x06,Data([0x55,0x04,0x03])) + der(0x0c,Data("Squirrel PKG Signing".utf8)))))
    let info = der(0x30,der(0x02,Data([0])) + commonName + der(0x30,rsa + der(0x03,Data([0]) + publicDER)) + der(0xa0,Data()))
    guard let signature = SecKeyCreateSignature(key,.rsaSignatureMessagePKCS1v15SHA256,info as CFData,&error) as Data? else { throw error!.takeRetainedValue() }
    let algorithm = der(0x30,der(0x06,Data([0x2a,0x86,0x48,0x86,0xf7,0x0d,0x01,0x01,0x0b])) + der(0x05,Data()))
    let request = der(0x30,info + algorithm + der(0x03,Data([0]) + signature))
    let base64 = request.base64EncodedString(options: [.lineLength64Characters,.endLineWithLineFeed])
    try ("-----BEGIN CERTIFICATE REQUEST-----\n" + base64 + "\n-----END CERTIFICATE REQUEST-----\n").write(to: output,atomically:true,encoding:.utf8)
    print("Public CSR: \(output.path); private key remains in the login keychain")
  }
}
