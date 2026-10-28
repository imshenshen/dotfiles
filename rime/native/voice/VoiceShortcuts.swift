import AppKit
import CoreGraphics
import ApplicationServices

struct VoiceShortcut: Codable, Equatable {
  var keyCode: UInt16?
  var modifiers: UInt
  var label: String
  // Optional for compatibility with previously saved shortcuts.
  var modifierKeyCode: UInt16? = nil
  static let option = VoiceShortcut(keyCode: nil, modifiers: NSEvent.ModifierFlags.option.rawValue, label: "右 ⌥", modifierKeyCode: 61)
  var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
  static var configured: VoiceShortcut {
    get {
      guard let data = VoiceSettings.defaults.data(forKey: "shortcut"),
            let value = try? JSONDecoder().decode(Self.self, from: data) else { return .option }
      return value
    }
    set { VoiceSettings.defaults.set(try? JSONEncoder().encode(newValue), forKey: "shortcut") }
  }
}

// Modifier-only gestures support a quick tap or a hold, firing exactly once.
// Device masks are defined by IOKit/hidsystem/IOLLEvent.h.
struct VoiceModifierGesture {
  enum Action: Equatable { case none, arm, trigger, release }
  private var down = false
  private var fired = false
  private var cancelled = false
  static func mask(_ code: UInt16) -> UInt {
    switch code {
    case 58: return 0x20; case 61: return 0x40
    case 59: return 0x01; case 62: return 0x2000
    case 56: return 0x02; case 60: return 0x04
    case 55: return 0x08; case 54: return 0x10
    default: return 0
    }
  }
  mutating func change(code: UInt16, rawFlags: UInt, shortcut: VoiceShortcut, recording: Bool) -> Action {
    let flags = NSEvent.ModifierFlags(rawValue: rawFlags).intersection([.option, .command, .control, .shift, .function])
    let sideMatches = shortcut.modifierKeyCode.map { rawFlags & Self.mask($0) != 0 } ?? true
    let pressed = flags == shortcut.flags && sideMatches
    if pressed && !down {
      down = true; fired = recording; cancelled = false
      return recording ? .trigger : .arm
    }
    if !pressed && down {
      down = false
      let trigger = !fired && !cancelled && flags.isEmpty
      fired = false; cancelled = false
      return trigger ? .trigger : .release
    }
    return .none
  }
  mutating func cancel() { cancelled = true }
  mutating func held() -> Bool {
    guard down, !fired, !cancelled else { return false }
    fired = true; return true
  }
  mutating func reset() { self = Self() }
}

// Accessibility already authorizes a modifying event tap. Input Monitoring is
// only a compatibility route for installations that granted it previously.
enum VoiceShortcutAuthorization {
  enum Mode: Equatable { case accessibility, listenOnly }
  static func mode(accessibility: Bool, inputMonitoring: @autoclosure () -> Bool) -> Mode? {
    if accessibility { return .accessibility }
    return inputMonitoring() ? .listenOnly : nil
  }
}

@MainActor final class VoiceGlobalShortcut {
  static let shared = VoiceGlobalShortcut()
  var onTrigger: (() -> Void)?
  var onEscape: (() -> Void)?
  var onPointer: ((CGPoint) -> Void)?
  var isRecording: () -> Bool = { false }
  var editingShortcut = false
  var shortcut = VoiceShortcut.configured
  private var tap: CFMachPort?
  private var source: CFRunLoopSource?
  private var arm: Timer?
  private var gesture = VoiceModifierGesture()
  private var consumeCombo = false
  var installed: Bool { tap != nil }
  private var authorization: VoiceShortcutAuthorization.Mode? {
    VoiceShortcutAuthorization.mode(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess())
  }
  var authorized: Bool { authorization != nil }
  func requestPermission() {
    if authorized { start(); return }
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
    start()
  }
  func local(_ event: NSEvent) {
    guard !installed, let cg = event.cgEvent else { return }
    _ = self.event(cg.type, cg)
  }
  func start() {
    shortcut = .configured
    guard let authorization else { stop(); return }
    let modifying = authorization == .accessibility
    if tap != nil && consumeCombo != modifying { stop() }
    guard tap == nil else { return }
    consumeCombo = modifying
    let types: [CGEventType] = [.flagsChanged, .keyDown, .keyUp, .leftMouseDown, .rightMouseDown]
    let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
    tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
      options: consumeCombo ? .defaultTap : .listenOnly, eventsOfInterest: mask,
      callback: { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let monitor = Unmanaged<VoiceGlobalShortcut>.fromOpaque(context).takeUnretainedValue()
        return MainActor.assumeIsolated {
          monitor.event(type, event) ? nil : Unmanaged.passUnretained(event)
        }
      }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    guard let tap else { return }
    source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    CGEvent.tapEnable(tap: tap, enable: true)
  }
  func stop() {
    arm?.invalidate(); arm = nil
    if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    tap = nil; source = nil; gesture.reset()
  }
  private func event(_ type: CGEventType, _ event: CGEvent) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false
    }
    if editingShortcut { arm?.invalidate(); arm = nil; gesture.reset(); return false }
    if type == .leftMouseDown || type == .rightMouseDown {
      arm?.invalidate(); arm = nil
      gesture.cancel()
      let point = event.location
      DispatchQueue.main.async { [weak self] in self?.onPointer?(point) }; return false
    }
    let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
      .intersection([.option, .command, .control, .shift, .function])
    let code = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
    if type == .keyDown, code == 53, flags.isEmpty, isRecording() {
      arm?.invalidate(); arm = nil; gesture.reset()
      DispatchQueue.main.async { [weak self] in self?.onEscape?() }
      return consumeCombo
    }
    if let key = shortcut.keyCode {
      guard flags == shortcut.flags, code == key else { return false }
      if type == .keyDown && event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { DispatchQueue.main.async { [weak self] in self?.onTrigger?() } }
      return consumeCombo && (type == .keyDown || type == .keyUp)
    }
    if type == .keyDown { arm?.invalidate(); arm = nil; gesture.cancel(); return false }
    guard type == .flagsChanged else { return false }
    switch gesture.change(code: code, rawFlags: UInt(event.flags.rawValue), shortcut: shortcut, recording: isRecording()) {
    case .arm:
      arm?.invalidate()
      arm = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { [weak self] _ in
        Task { @MainActor in
          guard let self, !self.editingShortcut, self.gesture.held() else { return }
          self.onTrigger?()
        }
      }
    case .trigger:
      arm?.invalidate(); arm = nil
      DispatchQueue.main.async { [weak self] in self?.onTrigger?() }
    case .release: arm?.invalidate(); arm = nil
    case .none: break
    }
    return false
  }
}

@MainActor final class VoiceShortcutRecorder: NSObject {
  let button = NSButton(title: VoiceShortcut.configured.label, target: nil, action: nil)
  private var monitor: Any?
  private var candidate: NSEvent.ModifierFlags?
  private var candidateCode: UInt16?
  override init() {
    super.init()
    button.bezelStyle = .rounded; button.target = self; button.action = #selector(record)
  }
  @objc private func record() {
    if monitor != nil { finish(nil); return }
    button.title = "请按快捷键…（Esc 取消）"
    VoiceGlobalShortcut.shared.editingShortcut = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
      var result: NSEvent? = event
      MainActor.assumeIsolated { if let self { result = self.capture(event) } }
      return result
    }
  }
  private func capture(_ event: NSEvent) -> NSEvent? {
    let flags = event.modifierFlags.intersection([.option, .command, .control, .shift, .function])
    if event.type == .keyDown {
      if event.keyCode == 53 { finish(nil); return nil }
      guard !flags.isEmpty else { button.title = "请使用修饰键或组合键"; return nil }
      let label = symbols(flags) + " " + (event.charactersIgnoringModifiers?.uppercased() ?? "按键 \(event.keyCode)")
      finish(VoiceShortcut(keyCode: event.keyCode, modifiers: flags.rawValue, label: label)); return nil
    }
    if !flags.isEmpty, VoiceModifierGesture.mask(event.keyCode) == 0 || event.modifierFlags.rawValue & VoiceModifierGesture.mask(event.keyCode) != 0 {
      candidate = flags
      let single = flags.rawValue.nonzeroBitCount == 1 && VoiceModifierGesture.mask(event.keyCode) != 0
      candidateCode = single ? event.keyCode : nil
    } else if let candidate {
      let side: String
      switch candidateCode {
      case 58, 59, 56, 55: side = "左 "
      case 61, 62, 60, 54: side = "右 "
      default: side = ""
      }
      finish(VoiceShortcut(keyCode: nil, modifiers: candidate.rawValue, label: side + symbols(candidate), modifierKeyCode: candidateCode))
    }
    return nil
  }
  private func symbols(_ flags: NSEvent.ModifierFlags) -> String {
    var text = ""
    if flags.contains(.control) { text += "⌃" }
    if flags.contains(.option) { text += "⌥" }
    if flags.contains(.shift) { text += "⇧" }
    if flags.contains(.command) { text += "⌘" }
    if flags.contains(.function) { text += "Fn" }
    return text
  }
  func finish(_ value: VoiceShortcut?) {
    if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    candidate = nil; candidateCode = nil; VoiceGlobalShortcut.shared.editingShortcut = false
    if let value { VoiceShortcut.configured = value }
    button.title = VoiceShortcut.configured.label
    VoiceGlobalShortcut.shared.shortcut = .configured
  }
}
