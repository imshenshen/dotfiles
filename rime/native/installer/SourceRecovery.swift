import Foundation
import Carbon
import Darwin

struct SourceRecoveryState: Codable {
  var token: String
  var generation: String
  var version: String
  var modes: [String]
  var phase: String
  var detail: String
}

enum SourceRecoveryPolicy {
  static let bundle = "im.rime.inputmethod.Squirrel"
  static let allowed = Set([bundle + ".Hans", bundle + ".Hant"])
  // An explicitly enabled parent and mode are required. Never enable a source
  // that the user removed or disabled while the installer was running.
  static func modes(_ entries: [[String: String]]) -> [String]? {
    let own = entries.filter { $0["Bundle ID"] == bundle }
    guard own.contains(where: { $0["InputSourceKind"] == "Keyboard Input Method" }) else { return nil }
    let modes = own.compactMap { $0["Input Mode"] }.sorted()
    guard !modes.isEmpty, Set(modes).count == modes.count,
          Set(modes).isSubset(of: allowed) else { return nil }
    return modes
  }
  static func ready(installerRunning: Bool, receipt: String?, state: SourceRecoveryState,
                    generation: String, modes: [String]?) -> Bool {
    !installerRunning && receipt == state.version && generation == state.generation && modes == state.modes
  }
}

protocol SourceRecoveryBackend {
  func validate(modes: [String]) throws
  func disableParent() throws
  func enableParent() throws
  func restoreModes(_ modes: [String]) throws
}

func rebuildSourceParent(_ backend: SourceRecoveryBackend, modes: [String]) throws {
  try backend.validate(modes: modes)
  // Re-enable even if disabling reports an error after partially changing state.
  do { try backend.disableParent() }
  catch {
    try? backend.enableParent()
    try? backend.restoreModes(modes)
    throw error
  }
  do { try backend.enableParent(); try backend.restoreModes(modes) }
  catch {
    try? backend.enableParent()
    try? backend.restoreModes(modes)
    throw error
  }
}

#if !SOURCE_RECOVERY_TEST
struct RecoveryFailure: Error, CustomStringConvertible {
  let description: String
  init(_ text: String) { description = text }
}

final class NativeSourceBackend: SourceRecoveryBackend {
  private var parent: TISInputSource?
  private func sources() -> [TISInputSource] { TISCreateInputSourceList(nil, true).takeRetainedValue() as! [TISInputSource] }
  private func id(_ source: TISInputSource) -> String {
    guard let p = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
    return Unmanaged<CFString>.fromOpaque(p).takeUnretainedValue() as String
  }
  private func enabled(_ source: TISInputSource) -> Bool {
    guard let p = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled) else { return false }
    return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(p).takeUnretainedValue())
  }
  private func checked(_ status: OSStatus, _ action: String) throws {
    guard status == noErr else { throw RecoveryFailure("\(action): \(status)") }
  }
  func validate(modes: [String]) throws {
    let all = sources()
    let roots = all.filter { id($0) == SourceRecoveryPolicy.bundle }
    guard roots.count == 1 else { throw RecoveryFailure("Ambiguous or missing parent source") }
    for mode in modes {
      guard all.filter({ id($0) == mode }).count == 1 else { throw RecoveryFailure("Ambiguous or missing mode") }
    }
    parent = roots[0]
  }
  func disableParent() throws {
    guard let parent else { throw RecoveryFailure("No validated parent") }
    try checked(TISDisableInputSource(parent), "disable parent")
  }
  func enableParent() throws {
    guard let parent else { throw RecoveryFailure("No validated parent") }
    try checked(TISEnableInputSource(parent), "enable parent")
  }
  func restoreModes(_ modes: [String]) throws {
    for source in sources() where SourceRecoveryPolicy.allowed.contains(id(source)) {
      let wanted = modes.contains(id(source))
      if enabled(source) != wanted {
        try checked(wanted ? TISEnableInputSource(source) : TISDisableInputSource(source), "restore mode")
      }
    }
  }
}

enum SourceRecovery {
  static let app = URL(fileURLWithPath: "/Library/Input Methods/Squirrel.app")
  static let label = "im.rime.inputmethod.Squirrel.SourceRecovery"
  static let home = URL(fileURLWithPath: String(cString: getpwuid(getuid())!.pointee.pw_dir))
  static let directory = home.appendingPathComponent("Library/Application Support/Squirrel/InstallationRecovery")
  static let stateURL = directory.appendingPathComponent("state.json")
  static let jobURL = directory.appendingPathComponent("task.plist")
  static var executable: String { app.appendingPathComponent("Contents/Helpers/SourceRecovery").path }

  static func command(_ executable: String, _ args: [String]) throws -> (Int32, Data) {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: executable); p.arguments = args
    p.standardOutput = out; p.standardError = FileHandle.nullDevice
    try p.run(); let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    return (p.terminationStatus, data)
  }
  static func info() throws -> (String, String) {
    guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
          let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
          info["CFBundleIdentifier"] as? String == SourceRecoveryPolicy.bundle,
          let version = info["CFBundleVersion"] as? String,
          let inode = try FileManager.default.attributesOfItem(atPath: app.path)[.systemFileNumber] as? NSNumber else {
      throw RecoveryFailure("Missing canonical installed app")
    }
    return (version, version + ":" + inode.stringValue)
  }
  static func entries() -> [[String: String]] {
    let domain = "com.apple.inputsources" as CFString
    _ = CFPreferencesAppSynchronize(domain)
    // Query cfprefsd, not its asynchronously flushed on-disk plist.
    return CFPreferencesCopyAppValue("AppleEnabledThirdPartyInputSources" as CFString, domain) as? [[String: String]] ?? []
  }
  static func receipt() -> String? {
    guard let (status, data) = try? command("/usr/sbin/pkgutil", ["--pkg-info-plist", SourceRecoveryPolicy.bundle]), status == 0,
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
    return plist["pkg-version"] as? String
  }
  static func installerRunning() throws -> Bool {
    for name in ["Installer", "installer"] {
      let (status, _) = try command("/usr/bin/pgrep", ["-x", name])
      guard status == 0 || status == 1 else { throw RecoveryFailure("Cannot query installer lifecycle") }
      if status == 0 { return true }
    }
    return false
  }
  static func privateDirectory() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }
  static func save(_ state: SourceRecoveryState) throws {
    try privateDirectory()
    try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stateURL.path)
  }
  static func load() throws -> SourceRecoveryState { try JSONDecoder().decode(SourceRecoveryState.self, from: Data(contentsOf: stateURL)) }
  static func pause(_ seconds: TimeInterval) {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { _ = CFRunLoopRunInMode(.defaultMode, min(0.1, end.timeIntervalSinceNow), false) }
  }
  static func withLock<T>(_ body: () throws -> T) throws -> T {
    try privateDirectory()
    let fd = open(directory.appendingPathComponent("lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
    guard fd >= 0 else { throw RecoveryFailure("Cannot open recovery lock") }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw RecoveryFailure("Cannot lock recovery") }
    defer { flock(fd, LOCK_UN) }
    return try body()
  }
  static func prepare() throws {
    let (version, generation) = try info()
    guard let modes = SourceRecoveryPolicy.modes(entries()) else {
      print("Source recovery skipped: no explicitly enabled Squirrel parent and modes"); return
    }
    let token: String? = try withLock {
      if let old = try? load(), old.generation == generation, old.phase == "completed" { return nil }
      let token = UUID().uuidString
      try save(SourceRecoveryState(token: token, generation: generation, version: version, modes: modes, phase: "pending", detail: "Waiting for Installer to exit and receipt to match"))
      return token
    }
    guard let token else { print("Source recovery already completed for this installation"); return }
    let uid = String(getuid())
    _ = try? command("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
    let log = directory.appendingPathComponent("recovery.log")
    if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: Data(), attributes: [.posixPermissions: 0o600]) }
    let job: [String: Any] = ["Label": label, "ProgramArguments": [executable, "--run", token], "RunAtLoad": true,
      "ProcessType": "Background", "StandardOutPath": log.path, "StandardErrorPath": log.path]
    try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0).write(to: jobURL, options: .atomic)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: jobURL.path)
    let (status, _) = try command("/bin/launchctl", ["bootstrap", "gui/\(uid)", jobURL.path])
    guard status == 0 else { throw RecoveryFailure("Cannot schedule recovery: \(status)") }
    print("Source recovery scheduled; it runs only after Installer exits")
  }
  static func run(_ token: String) throws {
    let deadline = Date().addingTimeInterval(300)
    var readySince: Date?
    while Date() < deadline {
      var state = try load()
      guard state.token == token, state.phase == "pending" else { return }
      let (_, generation) = try info()
      guard generation == state.generation else { return }
      let current = SourceRecoveryPolicy.modes(entries())
      let installing = try installerRunning()
      guard installing || current == state.modes else {
        // During package replacement an unrelated preference flush may lag.
        // Do not re-enable a source that is no longer explicitly enabled.
        state.phase = "skipped"; state.detail = "Enabled source choice changed before recovery"
        try save(state); return
      }
      if SourceRecoveryPolicy.ready(installerRunning: installing, receipt: receipt(), state: state, generation: generation, modes: current) {
        if readySince == nil { readySince = Date() }
        if Date().timeIntervalSince(readySince!) >= 2 { break }
      } else { readySince = nil }
      pause(0.25)
    }
    guard readySince != nil, Date() < deadline else {
      try withLock {
        var state = try load(); guard state.token == token else { return }
        state.phase = "deferred"; state.detail = "Installer still active or receipt not ready; no source changes made"
        try save(state)
      }; return
    }
    try withLock {
      var state = try load()
      guard state.token == token, state.phase == "pending" else { return }
      let (_, generation) = try info()
      guard SourceRecoveryPolicy.ready(installerRunning: try installerRunning(), receipt: receipt(), state: state, generation: generation, modes: SourceRecoveryPolicy.modes(entries())) else { return }
      state.phase = "running"; state.detail = "Refreshing only the enabled Squirrel parent and preserving its mode set"; try save(state)
      do {
        try rebuildSourceParent(NativeSourceBackend(), modes: state.modes)
        var stable = 0
        let end = Date().addingTimeInterval(30)
        while Date() < end {
          if SourceRecoveryPolicy.modes(entries()) == state.modes { stable += 1 } else { stable = 0 }
          if stable >= 4 {
            state.phase = "completed"; state.detail = "Parent refresh completed; original enabled mode records stable; native menu acceptance still required"
            try save(state); try? FileManager.default.removeItem(at: jobURL)
            print("Source recovery completed for \(state.version)"); return
          }
          pause(0.25)
        }
        throw RecoveryFailure("Source records did not stabilize after refresh")
      } catch {
        state.phase = "failed"; state.detail = String(describing: error); try save(state); throw error
      }
    }
  }
}

@main struct SourceRecoveryMain {
  static func main() {
    do {
      let args = CommandLine.arguments
      if args.count == 2 && args[1] == "--prepare" { try SourceRecovery.prepare() }
      else if args.count == 3 && args[1] == "--run" { try SourceRecovery.run(args[2]) }
      else { throw RecoveryFailure("Expected --prepare or --run token") }
    } catch { fputs("Source recovery: \(error)\n", stderr); exit(1) }
  }
}
#endif
