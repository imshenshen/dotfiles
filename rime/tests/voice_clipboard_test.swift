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
    print("PASS: Cmd+C copies whole result without selection, selected UTF-16 text otherwise; button copies all; success closes and failure retains result")
  }
}
