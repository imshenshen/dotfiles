import AppKit
@main struct CopyTest {
  @MainActor static func main() {
    let view = VoiceCopyTextView(); var output = "", closed = 0
    view.resultAvailable = { true }
    view.writeClipboard = { output = $0; return true }; view.copied = { closed += 1 }
    view.string = "第一行🙂\n第二行"
    view.setSelectedRange(NSRange(location: 0, length: 0)); view.copy(nil)
    precondition(output == view.string && closed == 1)
    view.setSelectedRange(NSRange(location: 3, length: 2)); view.copy(nil)
    precondition(output == "🙂" && closed == 2)
    view.copyAll(); precondition(output == view.string && closed == 3)
    let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
      timestamp: 0, windowNumber: 0, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8)!
    view.setSelectedRange(NSRange(location: 0, length: 0))
    precondition(view.performKeyEquivalent(with: event)); precondition(closed == 4 && output == view.string)
    view.writeClipboard = { _ in false }; view.copyAll(); precondition(closed == 4)
    view.string = ""; view.copyAll(); precondition(closed == 4)
    var dismissed = 0
    view.dismissed = { dismissed += 1 }
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
    let previousOutput = output
    precondition(view.performKeyEquivalent(with: escape)); precondition(dismissed == 1)
    view.cancelOperation(nil); precondition(dismissed == 2)
    view.keyDown(with: escape); precondition(dismissed == 3)
    precondition(output == previousOutput && closed == 4, "Escape must neither copy nor send text")
    print("PASS: Escape dismisses through key equivalent, cancel operation and keyDown without changing the clipboard")
    print("PASS: Cmd+C copies whole result without selection, selected UTF-16 text otherwise; button copies all; success closes and failure retains result")
  }
}
