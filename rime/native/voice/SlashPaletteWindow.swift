import AppKit

struct SlashPaletteSnapshot {
  var kind: RimeSlashCommand
  var query = ""
  var categories: [String] = []
  var selectedCategory: String?
  var symbols: [SlashSymbol] = []
  var gifs: [GIFItem] = []
  var selection = 0
  var pageStart = 0
  var pageCount = 1
  var itemCount = 0
  var message: String?
  var loading = false
  var provider: String?
}

@MainActor
final class SlashPaletteWindow: NSPanel {
  static let panelSize = NSSize(width: 900, height: 640)
  let canvas: SlashPaletteCanvas

  init() {
    canvas = SlashPaletteCanvas(frame: NSRect(origin: .zero, size: Self.panelSize))
    super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize),
               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    level = .floating
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    becomesKeyOnlyIfNeeded = true
    ignoresMouseEvents = false
    isMovableByWindowBackground = false
    appearance = NSAppearance(named: .darkAqua)
    contentView = canvas
  }

  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }

  func present(anchor: NSRect?) {
    let mouse = NSEvent.mouseLocation
    let point = anchor.flatMap { $0.isEmpty ? nil : NSPoint(x: $0.midX, y: $0.midY) } ?? mouse
    let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    guard let visible = screen?.visibleFrame else { orderFrontRegardless(); return }
    setFrame(Self.panelFrame(anchor: anchor, visible: visible, size: Self.panelSize, fallback: mouse),
             display: true)
    orderFrontRegardless()
  }

  static func panelFrame(anchor: NSRect?, visible: NSRect, size: NSSize, fallback: NSPoint) -> NSRect {
    var x = anchor.flatMap { $0.isEmpty ? nil : $0.minX } ?? fallback.x - 120
    var y: CGFloat
    if let anchor, !anchor.isEmpty, anchor.midY < visible.midY {
      y = anchor.maxY + 12
    } else if let anchor, !anchor.isEmpty {
      y = anchor.minY - size.height - 12
    } else {
      y = fallback.y - size.height / 2
    }
    x = min(max(x, visible.minX + 12), max(visible.minX + 12, visible.maxX - size.width - 12))
    y = min(max(y, visible.minY + 12), max(visible.minY + 12, visible.maxY - size.height - 12))
    return NSRect(x: x, y: y, width: size.width, height: size.height)
  }
}

@MainActor
final class SlashPaletteCanvas: NSView {
  static let sidebarWidth: CGFloat = 174
  static let queryHeight: CGFloat = 44
  static let footerHeight: CGFloat = 52
  static let columns = 6
  static let rows = 5
  static let pageSize = columns * rows

  var snapshot = SlashPaletteSnapshot(kind: .symbols) { didSet { needsDisplay = true } }
  var imageProvider: ((GIFItem) -> NSImage?)?
  var onCategory: ((String) -> Void)?
  var onActivate: ((Int) -> Void)?
  var onSettings: (() -> Void)?
  var onScroll: ((Int) -> Void)?

  private let accent = NSColor.controlAccentColor
  private let textColor = NSColor.white
  private let dimColor = NSColor.white.withAlphaComponent(0.56)
  private let faintColor = NSColor.white.withAlphaComponent(0.34)

  override var isFlipped: Bool { true }
  override var acceptsFirstResponder: Bool { false }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    setAccessibilityElement(true)
    setAccessibilityRole(.group)
    setAccessibilityLabel("符号与 GIF 搜索面板")
  }
  required init?(coder: NSCoder) { fatalError("init(coder:)") }

  private var gridRect: NSRect {
    NSRect(x: Self.sidebarWidth + 20, y: 82,
           width: bounds.width - Self.sidebarWidth - 40,
           height: bounds.height - 82 - Self.footerHeight - 8)
  }
  private var queryRect: NSRect {
    NSRect(x: Self.sidebarWidth + 20, y: 18, width: bounds.width - Self.sidebarWidth - 38, height: Self.queryHeight)
  }
  private var settingsRect: NSRect {
    NSRect(x: bounds.width - 142, y: bounds.height - 42, width: 124, height: 28)
  }
  private var categoryRects: [(String, NSRect)] {
    var result: [(String, NSRect)] = []
    var y: CGFloat = 116
    for category in snapshot.categories {
      result.append((category, NSRect(x: 16, y: y, width: Self.sidebarWidth - 30, height: 31)))
      y += 34
    }
    return result
  }
  private var visibleCount: Int {
    snapshot.kind == .symbols ? snapshot.symbols.count : snapshot.gifs.count
  }

  private func gridMetrics() -> (cell: NSSize, gap: CGFloat) {
    let gap: CGFloat = 12
    let rect = gridRect
    let cellWidth = floor((rect.width - gap * CGFloat(Self.columns - 1)) / CGFloat(Self.columns))
    let cellHeight = floor((rect.height - gap * CGFloat(Self.rows - 1)) / CGFloat(Self.rows))
    return (NSSize(width: cellWidth, height: cellHeight), gap)
  }

  private func index(at point: NSPoint) -> Int? {
    let rect = gridRect
    guard rect.contains(point) else { return nil }
    let metrics = gridMetrics()
    let column = Int((point.x - rect.minX) / (metrics.cell.width + metrics.gap))
    let row = Int((point.y - rect.minY) / (metrics.cell.height + metrics.gap))
    guard column >= 0, column < Self.columns, row >= 0, row < Self.rows else { return nil }
    let index = snapshot.pageStart + row * Self.columns + column
    return index < visibleCount ? index : nil
  }

  private func cellRect(_ index: Int) -> NSRect? {
    let offset = index - snapshot.pageStart
    guard offset >= 0, offset < Self.pageSize else { return nil }
    let metrics = gridMetrics()
    let column = offset % Self.columns, row = offset / Self.columns
    return NSRect(x: gridRect.minX + CGFloat(column) * (metrics.cell.width + metrics.gap),
                  y: gridRect.minY + CGFloat(row) * (metrics.cell.height + metrics.gap),
                  width: metrics.cell.width, height: metrics.cell.height)
  }

  override func draw(_ dirtyRect: NSRect) {
    let clip = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 22, yRadius: 22)
    NSGraphicsContext.saveGraphicsState()
    clip.addClip()
    let gradient = NSGradient(starting: NSColor(calibratedWhite: 0.17, alpha: 0.985),
                              ending: NSColor(calibratedWhite: 0.075, alpha: 0.985))!
    gradient.draw(in: bounds, angle: -90)
    drawSidebar()
    drawQuery()
    drawGrid()
    drawFooter()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.13).setStroke()
    clip.lineWidth = 1
    clip.stroke()
  }

  private func drawSidebar() {
    let header = snapshot.kind == .symbols ? "分类" : "GIF 搜索"
    drawText(header, at: NSRect(x: 24, y: 86, width: 130, height: 18), font: .systemFont(ofSize: 10, weight: .semibold),
             color: dimColor, paragraph: .byTruncatingTail)
    if snapshot.kind == .symbols {
      for (category, rect) in categoryRects {
        let selected = (snapshot.selectedCategory ?? "全部") == category
        if selected {
          NSColor.white.withAlphaComponent(0.13).setFill()
          NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
          accent.setFill()
          NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.minY + 7, width: 3, height: rect.height - 14),
                       xRadius: 1.5, yRadius: 1.5).fill()
        }
        drawText(category, at: rect.insetBy(dx: 14, dy: 6),
                 font: .systemFont(ofSize: 12.5, weight: selected ? .semibold : .regular),
                 color: selected ? textColor : dimColor, paragraph: .byTruncatingTail)
      }
    } else {
      drawText(snapshot.provider ?? "在线 GIF", at: NSRect(x: 24, y: 116, width: 130, height: 18),
               font: .systemFont(ofSize: 12.5, weight: .medium), color: textColor, paragraph: .byTruncatingTail)
      drawWrapped("关键词可输入英文。\n结果选中后复制到剪贴板，\n再回目标应用按 ⌘V。",
                  at: NSRect(x: 24, y: 146, width: 128, height: 96),
                  font: .systemFont(ofSize: 11), color: dimColor)
      drawText("隐私", at: NSRect(x: 24, y: 270, width: 130, height: 16),
               font: .systemFont(ofSize: 10, weight: .semibold), color: dimColor, paragraph: .byTruncatingTail)
      drawWrapped("搜索词会发送到所选服务；Key 仅保存在本机钥匙串。",
                  at: NSRect(x: 24, y: 290, width: 128, height: 66),
                  font: .systemFont(ofSize: 10.5), color: faintColor)
    }
    NSColor.white.withAlphaComponent(0.08).setFill()
    NSRect(x: Self.sidebarWidth, y: 74, width: 1, height: bounds.height - 74 - Self.footerHeight - 4).fill()
  }

  private func drawQuery() {
    let rect = queryRect
    NSColor.white.withAlphaComponent(0.075).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 13, yRadius: 13).fill()
    NSColor.white.withAlphaComponent(0.10).setStroke()
    let border = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 13, yRadius: 13)
    border.lineWidth = 1; border.stroke()

    // Magnifier
    let icon = NSBezierPath(ovalIn: NSRect(x: rect.minX + 17, y: rect.minY + 14, width: 14, height: 14))
    icon.lineWidth = 1.7; dimColor.setStroke(); icon.stroke()
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: rect.minX + 29, y: rect.minY + 27))
    handle.line(to: NSPoint(x: rect.minX + 35, y: rect.minY + 33))
    handle.lineWidth = 1.7; handle.lineCapStyle = .round; handle.stroke()

    let pillWidth: CGFloat = 56
    let textRect = NSRect(x: rect.minX + 48, y: rect.minY + 11,
                          width: rect.width - 48 - pillWidth - 24, height: 24)
    let query = snapshot.query
    drawText(query.isEmpty ? snapshot.kind.queryPlaceholder : query, at: textRect,
             font: .systemFont(ofSize: 15, weight: .medium), color: query.isEmpty ? dimColor : textColor,
             paragraph: .byTruncatingTail)
    if !query.isEmpty {
      let width = min(textRect.width, ceil((query as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .medium)]).width))
      let cursorX = textRect.minX + width + 2
      if cursorX < textRect.maxX {
        NSColor.white.withAlphaComponent(0.75).setFill()
        NSRect(x: cursorX, y: textRect.minY + 3, width: 1.5, height: textRect.height - 6).fill()
      }
    }

    let pill = NSRect(x: rect.maxX - pillWidth - 12, y: rect.minY + 11, width: pillWidth, height: 22)
    NSColor.white.withAlphaComponent(0.10).setFill()
    NSBezierPath(roundedRect: pill, xRadius: 11, yRadius: 11).fill()
    drawText(snapshot.kind.title, at: pill.insetBy(dx: 8, dy: 3),
             font: .systemFont(ofSize: 10.5, weight: .semibold), color: dimColor,
             paragraph: .byTruncatingTail, alignment: .center)
  }

  private func drawGrid() {
    let count = visibleCount
    if count == 0 {
      let message = snapshot.message ?? (snapshot.loading ? "正在搜索…" : "没有结果")
      drawWrapped(message, at: NSRect(x: gridRect.minX + 24, y: gridRect.minY + 60,
                                     width: gridRect.width - 48, height: 90),
                  font: .systemFont(ofSize: 14), color: dimColor, alignment: .center)
      return
    }
    let end = min(count, snapshot.pageStart + Self.pageSize)
    for index in snapshot.pageStart..<end {
      guard let rect = cellRect(index) else { continue }
      if snapshot.kind == .symbols {
        drawSymbol(index, in: rect)
      } else {
        drawGIF(index, in: rect)
      }
    }
  }

  private func drawSymbol(_ index: Int, in rect: NSRect) {
    guard index < snapshot.symbols.count else { return }
    let symbol = snapshot.symbols[index]
    let selected = index == snapshot.selection
    let path = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
    if selected {
      accent.withAlphaComponent(0.17).setFill(); path.fill()
      accent.withAlphaComponent(0.95).setStroke(); path.lineWidth = 1.7; path.stroke()
    } else {
      NSColor.white.withAlphaComponent(0.055).setFill(); path.fill()
    }
    let glyphRect = NSRect(x: rect.minX + 4, y: rect.minY + 7, width: rect.width - 8, height: rect.height - 28)
    let glyphFont = NSFont.systemFont(ofSize: 31, weight: .regular)
    let glyphSize = (symbol.glyph as NSString).size(withAttributes: [.font: glyphFont])
    (symbol.glyph as NSString).draw(at: NSPoint(x: rect.midX - glyphSize.width / 2,
                                                y: glyphRect.midY - glyphSize.height / 2),
                                    withAttributes: [.font: glyphFont, .foregroundColor: textColor])
    let label = symbol.nameZH.isEmpty ? symbol.hex : symbol.nameZH
    drawText(label, at: NSRect(x: rect.minX + 6, y: rect.maxY - 21, width: rect.width - 12, height: 14),
             font: .systemFont(ofSize: 9.5, weight: selected ? .medium : .regular),
             color: selected ? textColor : dimColor, paragraph: .byTruncatingTail, alignment: .center)
  }

  private func drawGIF(_ index: Int, in rect: NSRect) {
    guard index < snapshot.gifs.count else { return }
    let item = snapshot.gifs[index]
    let selected = index == snapshot.selection
    let path = NSBezierPath(roundedRect: rect, xRadius: 11, yRadius: 11)
    NSColor.white.withAlphaComponent(0.06).setFill(); path.fill()
    if let image = imageProvider?(item) {
      NSGraphicsContext.saveGraphicsState()
      path.addClip()
      let inner = rect.insetBy(dx: 3, dy: 3)
      let size = image.size
      let scale = min(inner.width / max(1, size.width), inner.height / max(1, size.height))
      let drawSize = NSSize(width: size.width * scale, height: size.height * scale)
      let drawRect = NSRect(x: inner.midX - drawSize.width / 2, y: inner.midY - drawSize.height / 2,
                            width: drawSize.width, height: drawSize.height)
      image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
      let fade = NSRect(x: rect.minX, y: rect.maxY - 28, width: rect.width, height: 28)
      NSGradient(starting: NSColor.clear, ending: NSColor.black.withAlphaComponent(0.62))?.draw(in: fade, angle: -90)
      drawText(item.title.isEmpty ? "GIF" : item.title,
               at: NSRect(x: rect.minX + 8, y: rect.maxY - 22, width: rect.width - 16, height: 15),
               font: .systemFont(ofSize: 9.5, weight: .medium), color: .white, paragraph: .byTruncatingTail)
      NSGraphicsContext.restoreGraphicsState()
    } else {
      drawText("GIF", at: rect.insetBy(dx: 8, dy: 8), font: .systemFont(ofSize: 13, weight: .semibold),
               color: dimColor, paragraph: .byTruncatingTail, alignment: .center)
    }
    if selected {
      accent.withAlphaComponent(0.95).setStroke(); path.lineWidth = 2; path.stroke()
    }
  }

  private func drawFooter() {
    let y = bounds.height - Self.footerHeight
    NSColor.white.withAlphaComponent(0.08).setFill()
    NSRect(x: 0, y: y, width: bounds.width, height: 1).fill()
    let status: String
    if let message = snapshot.message {
      status = message
    } else if snapshot.loading {
      status = "正在搜索…"
    } else if snapshot.kind == .symbols {
      status = "第 \(snapshot.pageStart / Self.pageSize + 1) / \(snapshot.pageCount) 页 · \(snapshot.itemCount) 个符号"
    } else {
      let provider = snapshot.provider.map { " · \($0)" } ?? ""
      status = "第 \(snapshot.pageStart / Self.pageSize + 1) / \(snapshot.pageCount) 页 · \(snapshot.itemCount) 个结果\(provider)"
    }
    drawText(status, at: NSRect(x: 24, y: y + 17, width: 250, height: 18),
             font: .systemFont(ofSize: 10.5), color: dimColor, paragraph: .byTruncatingTail)
    drawText(snapshot.kind.footerHint, at: NSRect(x: 286, y: y + 17, width: bounds.width - 520, height: 18),
             font: .systemFont(ofSize: 10.5), color: dimColor, paragraph: .byTruncatingTail, alignment: .center)
    if snapshot.kind == .gif {
      let rect = settingsRect
      NSColor.white.withAlphaComponent(0.09).setFill()
      NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
      drawText("GIF 设置…", at: rect.insetBy(dx: 9, dy: 6),
               font: .systemFont(ofSize: 10.5, weight: .medium), color: textColor,
               paragraph: .byTruncatingTail, alignment: .center)
    }
  }

  private func drawText(_ text: String, at rect: NSRect, font: NSFont, color: NSColor,
                        paragraph: NSLineBreakMode = .byTruncatingTail, alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = paragraph
    style.alignment = alignment
    (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
  }

  private func drawWrapped(_ text: String, at rect: NSRect, font: NSFont, color: NSColor,
                           alignment: NSTextAlignment = .left) {
    let style = NSMutableParagraphStyle()
    style.lineBreakMode = .byWordWrapping
    style.alignment = alignment
    style.lineSpacing = 2
    (text as NSString).draw(in: rect, withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
  }

  override func mouseDown(with event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    if snapshot.kind == .gif, settingsRect.contains(point) {
      onSettings?(); return
    }
    for (category, rect) in categoryRects where rect.contains(point) {
      onCategory?(category); return
    }
    if let index = index(at: point) {
      onActivate?(index)
    }
  }

  override func scrollWheel(with event: NSEvent) {
    guard event.scrollingDeltaY != 0 else { return }
    onScroll?(event.scrollingDeltaY > 0 ? -Self.columns : Self.columns)
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    if snapshot.kind == .gif { addCursorRect(settingsRect, cursor: .pointingHand) }
    for (_, rect) in categoryRects { addCursorRect(rect, cursor: .pointingHand) }
    let count = visibleCount
    let end = min(count, snapshot.pageStart + Self.pageSize)
    if snapshot.pageStart < end {
      for index in snapshot.pageStart..<end {
        if let rect = cellRect(index) { addCursorRect(rect, cursor: .pointingHand) }
      }
    }
  }
}
