import AppKit
import ApplicationServices
import Carbon

@MainActor final class VoiceAccessibilityHost: VoiceTextHost {
  private let element: AXUIElement
  let ownerPID: pid_t
  private init(_ element: AXUIElement, pid: pid_t) { self.element = element; ownerPID = pid }
  static var authorized: Bool { AXIsProcessTrusted() }
  static func requestPermission() {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(options)
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }
  private static func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
  }
  static func focused() -> VoiceAccessibilityHost? {
    guard authorized, !IsSecureEventInputEnabled(), let app = NSWorkspace.shared.frontmostApplication,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    guard let object = attribute(application, kAXFocusedUIElementAttribute as CFString),
          CFGetTypeID(object) == AXUIElementGetTypeID() else { return nil }
    let element = unsafeBitCast(object, to: AXUIElement.self)
    let role = attribute(element, kAXRoleAttribute as CFString) as? String
    let subrole = attribute(element, kAXSubroleAttribute as CFString) as? String
    guard subrole != kAXSecureTextFieldSubrole,
          [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "") else { return nil }
    var writable = DarwinBoolean(false)
    guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &writable) == .success,
          writable.boolValue else { return nil }
    var names: CFArray?
    guard AXUIElementCopyParameterizedAttributeNames(element, &names) == .success,
          (names as? [String])?.contains(kAXStringForRangeParameterizedAttribute) == true else { return nil }
    let host = VoiceAccessibilityHost(element, pid: app.processIdentifier)
    guard host.selection.location != NSNotFound, host.selection.length == 0 else { return nil }
    return host
  }
  var selection: NSRange {
    guard let object = Self.attribute(element, kAXSelectedTextRangeAttribute as CFString),
          CFGetTypeID(object) == AXValueGetTypeID() else { return NSRange(location: NSNotFound, length: 0) }
    var range = CFRange()
    guard AXValueGetValue(unsafeBitCast(object, to: AXValue.self), .cfRange, &range), range.location >= 0 else {
      return NSRange(location: NSNotFound, length: 0)
    }
    return NSRange(location: range.location, length: range.length)
  }
  var marked: NSRange { NSRange(location: NSNotFound, length: 0) }
  func text(in range: NSRange) -> String? {
    if range.length == 0 { return "" }
    var range = CFRange(location: range.location, length: range.length)
    guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
    var result: CFTypeRef?
    guard AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString,
                                                     parameter, &result) == .success else { return nil }
    return result as? String
  }
  func insert(_ text: String, replacing range: NSRange) {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ownerPID,
          let current = Self.focused(), CFEqual(current.element, element),
          range.location != NSNotFound else { return }
    var range = CFRange(location: range.location, length: range.length)
    guard let value = AXValueCreate(.cfRange, &range),
          AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else { return }
    _ = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
  }
  func mark(_ text: String, replacing range: NSRange) { /* AX is used only for final insertion. */ }
  func isFocused() -> Bool {
    guard let current = Self.focused() else { return false }
    return CFEqual(current.element, element)
  }
}
