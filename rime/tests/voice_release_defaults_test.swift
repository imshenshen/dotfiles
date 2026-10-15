import Foundation

@main struct ReleaseDefaultsTest {
  static func main() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("defaults.plist")
    let values: [String: Any] = ["provider": "doubao", "mixedSpacing": true, "pauseMilliseconds": 1600,
      "apiKey": "PUBLIC-TEST-MARKER", "doubaoAppID": "TEST", "inputDeviceUID": "TEST", "acceptanceFixtureEnabled": true]
    try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: file)
    let registered = VoiceSettings.releaseDefaults(at: file)
    precondition(Set(registered.keys) == Set(["provider", "mixedSpacing", "pauseMilliseconds"]))
    let suite = "im.rime.release-test.\(UUID().uuidString)"
    let settings = UserDefaults(suiteName: suite)!
    // Volatile domains exercise lookup precedence without writing any preference file.
    settings.setVolatileDomain(["provider": "apple", "mixedSpacing": false], forName: UserDefaults.argumentDomain)
    settings.register(defaults: registered)
    precondition(settings.string(forKey: "provider") == "apple")
    precondition(!settings.bool(forKey: "mixedSpacing"))
    precondition(settings.integer(forKey: "pauseMilliseconds") == 1600)
    precondition(VoiceSettings.releaseDefaults(at: directory.appendingPathComponent("missing")).isEmpty)
    print("PASS: packaged defaults fill missing preferences, preserve existing overrides and reject private settings")
  }
}
