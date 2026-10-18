import Foundation
import CoreAudio

struct VoiceDevice: Equatable {
  let id: AudioDeviceID
  let uid: String
  let name: String
  let channels: Int
  var bluetooth: Bool {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var transport: UInt32 = 0
    var size = UInt32(MemoryLayout.size(ofValue: transport))
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, &transport) == noErr else { return false }
    return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
  }
}

struct VoiceAudioConfiguration: Equatable {
  let deviceID: AudioDeviceID
  let sampleRate: Double
  let channels: UInt32
  var usable: Bool { deviceID != 0 && sampleRate.isFinite && sampleRate > 0 && channels > 0 }
  func accepts(_ current: Self?) -> Bool { usable && current?.usable == true && current == self }
}

enum VoiceDevices {
  static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
                                             mElement: kAudioObjectPropertyElementMain)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout.size(ofValue: value))
    let result = withUnsafeMutablePointer(to: &value) {
      AudioObjectGetPropertyData(id, &address, 0, nil, &size, $0)
    }
    guard result == noErr else { return nil }
    return value?.takeRetainedValue() as String?
  }
  static func inputChannels(_ id: AudioDeviceID) -> Int {
    var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
      mScope: kAudioDevicePropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &size) == noErr, size > 0 else { return 0 }
    let storage = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { storage.deallocate() }
    guard AudioObjectGetPropertyData(id, &address, 0, nil, &size, storage) == noErr else { return 0 }
    return UnsafeMutableAudioBufferListPointer(storage.assumingMemoryBound(to: AudioBufferList.self))
      .reduce(0) { $0 + Int($1.mNumberChannels) }
  }
  static func inputs() -> [VoiceDevice] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    let result = ids.withUnsafeMutableBytes {
      AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!)
    }
    guard result == noErr else { return [] }
    return ids.compactMap { id in
      let channels = inputChannels(id)
      guard channels > 0, let uid = string(id, kAudioDevicePropertyDeviceUID),
            let name = string(id, kAudioObjectPropertyName) else { return nil }
      return VoiceDevice(id: id, uid: uid, name: name, channels: channels)
    }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }
  static func defaultInputID() -> AudioDeviceID {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout.size(ofValue: id))
    _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
    return id
  }
  static func selected(uid: String) -> VoiceDevice? {
    let devices = inputs()
    return uid.isEmpty ? devices.first { $0.id == defaultInputID() } : devices.first { $0.uid == uid }
  }
}

enum VoiceSettings {
  static let defaults: UserDefaults = {
    let settings = UserDefaults(suiteName: "im.rime.inputmethod.Squirrel.Voice")!
    if let url = Bundle.main.url(forResource: "VoiceDefaults", withExtension: "plist") {
      settings.register(defaults: releaseDefaults(at: url))
    }
    return settings
  }()
  static func releaseDefaults(at url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url),
          let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
    // Registration defaults never replace a user's persistent preferences.
    let allowed = Set(["provider", "doubaoResource", "doubaoAuthMode", "shortcut", "mixedSpacing", "pauseMilliseconds", "removeDisfluencies"])
    return values.filter { allowed.contains($0.key) }
  }
  static var deviceUID: String {
    get { defaults.string(forKey: "inputDeviceUID") ?? "" }
    set { defaults.set(newValue, forKey: "inputDeviceUID") }
  }
  static var provider: String {
    get { defaults.string(forKey: "provider") == "doubao" ? "doubao" : "apple" }
    set { defaults.set(newValue, forKey: "provider") }
  }
  static var doubaoAppID: String {
    get { defaults.string(forKey: "doubaoAppID") ?? "" }
    set { defaults.set(newValue, forKey: "doubaoAppID") }
  }
  static var doubaoResource: String {
    get { defaults.string(forKey: "doubaoResource") ?? "volc.seedasr.sauc.duration" }
    set { defaults.set(newValue, forKey: "doubaoResource") }
  }
  static var mixedSpacing: Bool {
    get { defaults.object(forKey: "mixedSpacing") == nil ? true : defaults.bool(forKey: "mixedSpacing") }
    set { defaults.set(newValue, forKey: "mixedSpacing") }
  }
  static var removeDisfluencies: Bool {
    get { defaults.bool(forKey: "removeDisfluencies") }
    set { defaults.set(newValue, forKey: "removeDisfluencies") }
  }
  static var rewriteModel: String {
    get { defaults.string(forKey: "rewriteModel") ?? "" }
    set { defaults.set(newValue, forKey: "rewriteModel") }
  }
  static var pauseMilliseconds: Int {
    get { let n = defaults.integer(forKey: "pauseMilliseconds"); return [800, 1600, 2500, 4000].contains(n) ? n : 1600 }
    set { defaults.set(newValue, forKey: "pauseMilliseconds") }
  }
  // Explicit developer opt-in. Only a known, local acceptance fixture is read.
  static var acceptanceFixture: String? {
    let path = "/tmp/rime-voice-acceptance/speech.aiff"
    return defaults.bool(forKey: "acceptanceFixtureEnabled") && FileManager.default.isReadableFile(atPath: path) ? path : nil
  }
}
