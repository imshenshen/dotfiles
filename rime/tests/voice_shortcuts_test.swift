import AppKit
// A separate suite ensures this test never changes the user's shortcut.
enum VoiceSettings { static let defaults = UserDefaults(suiteName: "im.rime.ShortcutRegression")! }
@main struct ShortcutTest {
  static func main() throws {
    let option = NSEvent.ModifierFlags.option.rawValue
    var gesture = VoiceModifierGesture()
    precondition(gesture.change(code: 58, rawFlags: option | 0x20, shortcut: .option, recording: false) == .arm)
    precondition(gesture.change(code: 58, rawFlags: 0, shortcut: .option, recording: false) == .trigger)
    precondition(!gesture.held())
    precondition(gesture.change(code: 61, rawFlags: option | 0x40, shortcut: .option, recording: false) == .arm)
    precondition(gesture.held()); precondition(!gesture.held())
    precondition(gesture.change(code: 61, rawFlags: 0, shortcut: .option, recording: true) == .release)
    let left = VoiceShortcut(keyCode: nil, modifiers: option, label: "left", modifierKeyCode: 58)
    precondition(gesture.change(code: 61, rawFlags: option | 0x40, shortcut: left, recording: false) == .none)
    precondition(gesture.change(code: 61, rawFlags: 0, shortcut: left, recording: false) == .none)
    precondition(gesture.change(code: 58, rawFlags: option | 0x20, shortcut: left, recording: false) == .arm)
    gesture.cancel(); precondition(!gesture.held())
    precondition(gesture.change(code: 58, rawFlags: 0, shortcut: left, recording: false) == .release)
    precondition(gesture.change(code: 58, rawFlags: option | 0x20, shortcut: left, recording: true) == .trigger)
    precondition(gesture.change(code: 58, rawFlags: 0, shortcut: left, recording: false) == .release)
    let old = Data("{\"modifiers\":524288,\"label\":\"Option\"}".utf8)
    let decoded = try JSONDecoder().decode(VoiceShortcut.self, from: old)
    precondition(decoded.modifierKeyCode == nil)
    print("PASS: quick tap, hold once, stop once, left/right isolation, combo cancellation, old configuration")
  }
}
