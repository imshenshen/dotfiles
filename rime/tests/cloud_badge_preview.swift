// Compile with the actual CloudCandidateBadge helper extracted from the patched
// SquirrelPanel.swift. Render both appearances and verify metadata stays hidden.
import AppKit

extension NSAttributedString.Key {
  static let noBreak = NSAttributedString.Key("noBreak")
}

@main
struct CloudBadgePreview {
  static func main() throws {
    _ = NSApplication.shared
    let output = CommandLine.arguments[1]
    let marker = "\u{E000}3\u{E001}"
    precondition(CloudCandidateBadge.decode(marker).isCloud)
    precondition(CloudCandidateBadge.decode(marker + "原注释").text == "原注释")
    precondition(!CloudCandidateBadge.decode("原注释").isCloud)
    precondition(!CloudCandidateBadge.decode("\u{E000}x\u{E001}原注释").isCloud)

    for dark in [false, true] {
      let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
      NSApp.appearance = appearance
      let image = NSImage(size: NSSize(width: 720, height: 112))
      appearance.performAsCurrentDrawingAppearance {
        image.lockFocus()
        (dark ? NSColor(calibratedWhite: 0.13, alpha: 1) : .white).setFill()
        NSRect(x: 0, y: 0, width: 720, height: 112).fill()
        for highlighted in [false, true] {
          let y: CGFloat = highlighted ? 58 : 8
          if highlighted {
            (dark ? NSColor(calibratedRed: 0.14, green: 0.22, blue: 0.32, alpha: 1)
                  : NSColor(calibratedRed: 0.9, green: 0.94, blue: 1, alpha: 1)).setFill()
            NSBezierPath(roundedRect: NSRect(x: 8, y: y, width: 700, height: 42), xRadius: 8, yRadius: 8).fill()
          }
          let color: NSColor = highlighted ? .systemBlue : (dark ? .white : .darkGray)
          let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: color]
          let line = NSMutableAttributedString(string: "1 梦幻模拟战 ", attributes: attrs)
          let widthBefore = line.size().width
          CloudCandidateBadge.append(to: line, attributes: attrs)
          let badge = line.attribute(.attachment, at: line.length - 1, effectiveRange: nil) as! NSTextAttachment
          precondition(badge.bounds.width == 12 && badge.bounds.height == 9 && badge.bounds.minY < 0)
          precondition(line.size().width - widthBefore < 16)
          line.append(NSAttributedString(string: "   2 梦幻   3 梦幻模拟战号 ", attributes: attrs))
          CloudCandidateBadge.append(to: line, attributes: attrs)
          line.append(NSAttributedString(string: "   4 勐焕", attributes: attrs))
          precondition(!line.string.contains("搜狗") && !line.string.contains("Google") && !line.string.contains("\u{E000}"))
          line.draw(at: NSPoint(x: 16, y: y + 7))
        }
        image.unlockFocus()
      }
      guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("No rendered preview") }
      try data.write(to: URL(fileURLWithPath: output + (dark ? "/cloud-badge-dark.png" : "/cloud-badge-light.png")))
    }
    print("PASS: hidden provider metadata, preserved native comments, compact bottom-offset image badge, light/dark previews")
  }
}
