import AppKit
@main struct PlacementTest {
  static func main() {
    let main = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let right = CGRect(x: 1920, y: -200, width: 2560, height: 1440)
    let left = CGRect(x: -1600, y: 200, width: 1600, height: 900)
    let upper = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
    let screens = [main, right, left, upper]
    // The caret wins even when the mouse remains on the primary display.
    precondition(VoiceHUDPlacement.screenIndex(frames: screens,
      input: CGRect(x: 2400, y: 500, width: 0, height: 22), focused: nil, pointer: .zero) == 1)
    precondition(VoiceHUDPlacement.screenIndex(frames: screens,
      input: CGRect(x: -1400, y: 700, width: 2, height: 20), focused: nil, pointer: .zero) == 2)
    let quartz = CGRect(x: 600, y: -700, width: 600, height: 300)
    let cocoa = VoiceHUDPlacement.cocoaRect(quartz, primary: main)
    precondition(cocoa.minY == 1480)
    precondition(VoiceHUDPlacement.screenIndex(frames: screens, input: nil,
      focused: cocoa, pointer: .zero) == 3)
    // Focused windows that straddle monitors use the largest overlap.
    precondition(VoiceHUDPlacement.screenIndex(frames: screens, input: .zero,
      focused: CGRect(x: 1800, y: 100, width: 1000, height: 600), pointer: .zero) == 1)
    precondition(VoiceHUDPlacement.screenIndex(frames: screens, input: nil,
      focused: nil, pointer: CGPoint(x: -500, y: 400)) == 2)
    // Missing/disconnected display and unknown/invalid coordinates are safe.
    precondition(VoiceHUDPlacement.screenIndex(frames: [main], input: CGRect(x: 2400, y: 500, width: 2, height: 20),
      focused: nil, pointer: CGPoint(x: 2400, y: 0)) == 0)
    precondition(VoiceHUDPlacement.screenIndex(frames: [], input: nil, focused: nil, pointer: .zero) == nil)
    let visible = CGRect(x: -1600, y: 225, width: 1600, height: 850)
    let small = VoiceHUDPlacement.panelFrame(size: CGSize(width: 180, height: 56), visible: visible)
    let expanded = VoiceHUDPlacement.panelFrame(size: CGSize(width: 360, height: 268), visible: visible)
    precondition(small.midX == visible.midX && expanded.midX == visible.midX)
    precondition(small.minY == expanded.minY && small.minY == visible.minY+18)
    precondition(visible.contains(small) && visible.contains(expanded))
    print("PASS: input screen wins over primary/mouse, left/right/upper displays, AX coordinate conversion, largest overlap, disconnect fallback and bottom-anchored expansion")
  }
}
