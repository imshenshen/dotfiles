import AppKit
import ApplicationServices

// AppKit screen coordinates are bottom-left based. AX rectangles use the
// primary display's top-left origin, including negative coordinates off-screen.
enum VoiceHUDPlacement {
  static func cocoaRect(_ rectangle: CGRect, primary: CGRect) -> CGRect {
    CGRect(x: rectangle.minX, y: primary.maxY-rectangle.maxY,
           width: rectangle.width, height: rectangle.height)
  }
  private static func usable(_ rectangle: CGRect) -> Bool {
    [rectangle.minX, rectangle.minY, rectangle.width, rectangle.height].allSatisfy(\.isFinite) &&
      !rectangle.isNull && rectangle.width >= 0 && rectangle.height >= 0 &&
      (rectangle.width > 0 || rectangle.height > 0)
  }
  static func screenIndex(frames: [CGRect], input: CGRect?, focused: CGRect?, pointer: CGPoint) -> Int? {
    for rectangle in [input, focused].compactMap({ $0 }) where usable(rectangle) {
      // Zero-width caret rectangles still identify a screen.
      let rect = CGRect(x: rectangle.minX, y: rectangle.minY,
                        width: max(1, rectangle.width), height: max(1, rectangle.height))
      let matches = frames.indices.map { index -> (Int, CGFloat) in
        let overlap = frames[index].intersection(rect)
        return (index, overlap.isNull ? 0 : overlap.width * overlap.height)
      }
      if let best = matches.max(by: { $0.1 < $1.1 }), best.1 > 0 { return best.0 }
    }
    return frames.firstIndex(where: { $0.contains(pointer) }) ?? frames.indices.first
  }
  static func panelFrame(size: CGSize, visible: CGRect) -> CGRect {
    let width = min(size.width, visible.width), height = min(size.height, visible.height)
    return CGRect(x: visible.midX-width/2, y: min(visible.minY+18, visible.maxY-height), width: width, height: height)
  }
  @MainActor static func focusedBounds() -> CGRect? {
    guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
          app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    AXUIElementSetMessagingTimeout(application, 0.03)
    func attribute(_ element: AXUIElement, _ name: CFString) -> CFTypeRef? {
      var value: CFTypeRef?
      return AXUIElementCopyAttributeValue(element, name, &value) == .success ? value : nil
    }
    for name in [kAXFocusedUIElementAttribute, kAXFocusedWindowAttribute] {
      guard let object = attribute(application, name as CFString),
            CFGetTypeID(object) == AXUIElementGetTypeID() else { continue }
      let element = unsafeBitCast(object, to: AXUIElement.self)
      AXUIElementSetMessagingTimeout(element, 0.03)
      guard let position = attribute(element, kAXPositionAttribute as CFString),
            let size = attribute(element, kAXSizeAttribute as CFString),
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { continue }
      var point = CGPoint.zero, dimensions = CGSize.zero
      guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &point),
            AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions) else { continue }
      let rect = CGRect(origin: point, size: dimensions)
      if usable(rect), let primary = NSScreen.screens.first { return cocoaRect(rect, primary: primary.frame) }
    }
    return nil
  }
}
