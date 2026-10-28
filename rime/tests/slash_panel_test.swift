import AppKit

@main struct SlashPanelTest {
  @MainActor static func main() {
    _ = NSApplication.shared
    let panel = SlashPaletteWindow()
    precondition(!panel.canBecomeKey, "palette must never take key focus")
    precondition(!panel.canBecomeMain, "palette must never take main-window focus")
    precondition(panel.styleMask.contains(.nonactivatingPanel))
    precondition(panel.level == .floating)
    precondition(panel.collectionBehavior.contains(.canJoinAllSpaces))
    precondition(panel.contentView === panel.canvas)
    precondition(panel.canvas.acceptsFirstMouse(for: nil))
    precondition(!panel.canvas.acceptsFirstResponder)
    precondition(panel.canvas.subviews.isEmpty, "query line is display-only, not an editable field")
    precondition(SlashPaletteCanvas.pageSize == 30)

    let size = SlashPaletteWindow.panelSize
    let visible = NSRect(x: 0, y: 0, width: 1440, height: 875)
    let lower = SlashPaletteWindow.panelFrame(
      anchor: NSRect(x: 100, y: 100, width: 2, height: 18),
      visible: visible, size: size, fallback: NSPoint(x: 400, y: 400))
    precondition(lower.minX == 100 && lower.minY == 130 && lower.size == size,
                 "caret in lower half expands upward: \(lower)")
    let upper = SlashPaletteWindow.panelFrame(
      anchor: NSRect(x: 100, y: 700, width: 2, height: 18),
      visible: visible, size: size, fallback: NSPoint(x: 400, y: 400))
    precondition(upper.minX == 100 && upper.maxY == 688 && upper.size == size,
                 "caret in upper half expands downward: \(upper)")
    let offscreen = SlashPaletteWindow.panelFrame(
      anchor: NSRect(x: 2400, y: 100, width: 2, height: 18),
      visible: visible, size: size, fallback: NSPoint(x: 2400, y: 100))
    precondition(offscreen.minX == 528 && offscreen.maxX <= visible.maxX - 12,
                 "panel is clamped to the visible frame: \(offscreen)")
    let fallback = SlashPaletteWindow.panelFrame(
      anchor: nil, visible: visible, size: size, fallback: NSPoint(x: 0, y: 0))
    precondition(fallback.minX >= 12 && fallback.minY >= 12)
    precondition(fallback.maxX <= visible.maxX - 12 && fallback.maxY <= visible.maxY - 12)

    panel.canvas.snapshot = SlashPaletteSnapshot(kind: .symbols)
    panel.canvas.snapshot.query = "copyright"
    precondition(panel.canvas.snapshot.query == "copyright")
    print("PASS: nonactivating non-key panel, display-only query, first-mouse clicks, caret-aware placement and visible-frame clamping")
  }
}
