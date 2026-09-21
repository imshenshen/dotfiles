import AppKit
import CoreText

final class BarPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
class BarBackground: NSView {
    var settings: (() -> Void)?
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        item.target = self; menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func openSettings() { settings?() }
}
final class SpaceButton: NSButton {
    var space: Space
    var pick: (Space, Bool) -> Void
    var settings: () -> Void
    weak var surface: SpaceSurface?
    private var tracking: NSTrackingArea?
    var hovered = false
    private struct TextLayout {
        let line: CTLine
        let width: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }
    private struct LayoutKey: Equatable {
        let hint: String
        let name: String
        let fontSize: CGFloat
        let labelWidth: CGFloat
    }
    private var layoutKey: LayoutKey?
    private var hintLayout: TextLayout?
    private var labelLayout: TextLayout?
    private(set) var textLayoutBuildCount = 0
    init(space: Space, pick: @escaping (Space, Bool) -> Void, settings: @escaping () -> Void) {
        self.space = space; self.pick = pick; self.settings = settings
        super.init(frame: .zero)
        isBordered = false; title = ""; target = self; action = #selector(pressed)
        update(space)
    }
    func update(_ value: Space) {
        if value.name != space.name || value.hint != space.hint { invalidateTextLayout() }
        space = value
        toolTip = "\(space.index) · \(space.name)\n点击切换 · Option 点击重命名 · 右键设置"
        setAccessibilityLabel("\(space.name)，Space \(space.index)" + (space.focused ? "，当前焦点" : space.visible ? "，可见" : ""))
        needsDisplay = true
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func pressed() { pick(space, NSApp.currentEvent?.modifierFlags.contains(.option) == true) }
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let rename = NSMenuItem(title: "重命名 \(space.name)…", action: #selector(renameSpace), keyEquivalent: "")
        rename.target = self; menu.addItem(rename); menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    @objc private func renameSpace() { pick(space, true) }
    @objc private func openSettings() { settings() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; surface?.invalidateBackground(of: self) }
    override func mouseExited(with event: NSEvent) { hovered = false; surface?.invalidateBackground(of: self) }
    override func draw(_ dirtyRect: NSRect) {
        guard let surface else { return }
        let appearance = surface.barAppearance
        let overlap = surface.selectionRect?.intersection(frame).width ?? 0
        let fraction = min(1, max(0, overlap / max(1, frame.width)))
        let color = appearance.text.interpolated(to: appearance.selectedText, fraction: fraction)
        let hintSize = max(8, floor(appearance.fontSize * 0.73))
        let labelX = hintSize + 9
        let hintRect = NSRect(x: 5, y: bounds.height - hintSize - 4, width: hintSize + 6, height: hintSize + 2)
        let labelRect = NSRect(x: labelX, y: 2, width: max(0, bounds.width - labelX - 7), height: bounds.height - 4)
        ensureTextLayout(fontSize: appearance.fontSize, hintSize: hintSize, labelWidth: labelRect.width)
        if let hintLayout {
            Self.draw(layout: hintLayout, rect: hintRect, color: color.withAlphaComponent(color.alphaComponent * 0.75), centered: false)
        }
        if let labelLayout {
            Self.draw(layout: labelLayout, rect: labelRect, color: color, centered: true)
        }
    }
    func invalidateTextLayout() {
        layoutKey = nil
        hintLayout = nil
        labelLayout = nil
    }
    private func ensureTextLayout(fontSize: CGFloat, hintSize: CGFloat, labelWidth: CGFloat) {
        let key = LayoutKey(hint: space.hint, name: space.name, fontSize: fontSize, labelWidth: labelWidth.rounded(.toNearestOrAwayFromZero))
        guard key != layoutKey else { return }
        let hintFont = CTFontCreateWithName("Menlo" as CFString, hintSize, nil)
        let labelFont = CTFontCreateWithName(NSFont.systemFont(ofSize: fontSize, weight: .medium).fontName as CFString, fontSize, nil)
        hintLayout = Self.makeLayout(text: space.hint, font: hintFont, maximumWidth: nil)
        labelLayout = Self.makeLayout(text: space.name, font: labelFont, maximumWidth: max(0, labelWidth))
        layoutKey = key
        textLayoutBuildCount += 1
    }
    private static func makeLayout(text: String, font: CTFont, maximumWidth: CGFloat?) -> TextLayout {
        // The glyph layout has no fixed foreground color. CoreText takes the
        // current CGContext fill color, so the same CTLine can be reused while
        // the selection pill changes the text color on every animation frame.
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        let full = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let line: CTLine
        if let maximumWidth, CTLineGetTypographicBounds(full, nil, nil, nil) > maximumWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(full, maximumWidth, .end, ellipsis) ?? ellipsis
        } else {
            line = full
        }
        var ascent: CGFloat = 0; var descent: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
        return TextLayout(line: line, width: width, ascent: ascent, descent: descent)
    }
    private static func draw(layout: TextLayout, rect: CGRect, color: NSColor, centered: Bool) {
        guard rect.width > 0, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: rect)
        // Flip the glyph coordinate system around this text box. AppKit's
        // layer-backed drawing records a display list, so ctm.d alone does not
        // describe the final glyph orientation on screen.
        context.translateBy(x: 0, y: 2 * rect.midY)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.setFillColor(color.cgColor)
        context.textPosition = CGPoint(x: rect.minX + (centered ? max(0, (rect.width - layout.width) / 2) : 0), y: rect.midY - (layout.ascent - layout.descent) / 2)
        CTLineDraw(layout.line, context)
        context.restoreGState()
    }

}
final class SpaceSurface: BarBackground {
    var barAppearance = Appearance()
    var preferredFramesPerSecond = 60
    private var motion: SelectionMotion?
    private var timer: Timer?
    private var lastTick = 0.0
    var selectionRect: CGRect? { motion?.rect }
    deinit { timer?.invalidate() }
    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func select(_ rect: CGRect?, animated: Bool) {
        let oldRect = selectionRect
        guard let rect else { stop(); motion = nil; redraw(from: oldRect, to: nil); return }
        guard animated, barAppearance.animation, !reducedMotion, motion != nil else {
            stop(); motion = SelectionMotion(rect: rect); redraw(from: oldRect, to: rect); return
        }
        guard motion?.target != rect else { return }
        if timer != nil { tick() }
        motion?.target = rect
        if timer == nil {
            lastTick = ProcessInfo.processInfo.systemUptime
            let interval = 1.0 / Double(max(30, min(120, preferredFramesPerSecond)))
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.001; timer = t
            RunLoop.main.add(t, forMode: .common)
        }
        redraw(from: oldRect, to: selectionRect)
    }
    private func tick() {
        let oldRect = selectionRect
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.1, max(0, now - lastTick)); lastTick = now
        if !barAppearance.animation || reducedMotion {
            if let target = motion?.target { motion = SelectionMotion(rect: target) }
            stop()
        } else if motion?.advance(dt: dt, speed: barAppearance.speed) == true { stop() }
        redraw(from: oldRect, to: selectionRect)
    }
    func stop() { timer?.invalidate(); timer = nil }
    func invalidateBackground(of button: SpaceButton) { setNeedsDisplay(button.frame.insetBy(dx: -1, dy: -1)) }
    func invalidateAll() {
        needsDisplay = true
        subviews.forEach {
            ($0 as? SpaceButton)?.invalidateTextLayout()
            $0.needsDisplay = true
        }
    }
    private func redraw(from oldRect: CGRect?, to newRect: CGRect?) {
        let changed = [oldRect, newRect].compactMap { $0 }.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -2, dy: -1)
        if !changed.isNull { setNeedsDisplay(changed) }
        for button in subviews.compactMap({ $0 as? SpaceButton }) where
            (oldRect?.intersects(button.frame) == true) || (newRect?.intersects(button.frame) == true) {
            button.needsDisplay = true
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        for button in subviews.compactMap({ $0 as? SpaceButton }) where button.frame.intersects(dirtyRect) {
            let rect = button.frame.insetBy(dx: 0.5, dy: 1)
            let shape = NSBezierPath(roundedRect: rect, xRadius: min((bounds.height - 2) / 2, barAppearance.radius), yRadius: min((bounds.height - 2) / 2, barAppearance.radius))
            let color = barAppearance.inactive.color
            (button.hovered ? color.blended(withFraction: 0.12, of: .white) ?? color : color).setFill(); shape.fill()
            if button.space.visible && !button.space.focused { barAppearance.text.color.withAlphaComponent(0.65).setStroke(); shape.lineWidth = 1; shape.stroke() }
        }
        if let selectionRect {
            barAppearance.selection.color.setFill()
            NSBezierPath(roundedRect: selectionRect, xRadius: min((bounds.height - 2) / 2, barAppearance.radius), yRadius: min((bounds.height - 2) / 2, barAppearance.radius)).fill()
        }
    }
}
final class BarWindow {
    let panel: BarPanel
    private let background = BarBackground()
    private let scroll = NSScrollView()
    private let content = SpaceSurface()
    private var buttons: [Int: SpaceButton] = [:]
    init() {
        panel = BarPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false; panel.isMovable = false; panel.title = "SpaceBar"
        background.wantsLayer = true; panel.contentView = background
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = false
        scroll.documentView = content; background.addSubview(scroll)
    }
    func render(spaces: [Space], screen: NSScreen, appearance: Appearance, settings: @escaping () -> Void, pick: @escaping (Space, Bool) -> Void) {
        guard !spaces.isEmpty, !spaces.contains(where: { $0.visible && $0.fullscreen }) else { content.stop(); panel.orderOut(nil); return }
        let wasVisible = panel.isVisible
        background.settings = settings; content.settings = settings
        background.layer?.backgroundColor = appearance.background.color.cgColor; background.layer?.cornerRadius = min(appearance.effectiveHeight / 2, appearance.radius)
        let appearanceChanged = content.barAppearance != appearance
        content.barAppearance = appearance
        content.preferredFramesPerSecond = screen.maximumFramesPerSecond
        if appearanceChanged { content.invalidateAll() }
        let height = appearance.effectiveHeight
        let itemHeight = height - 6
        let maxWidth = max(100, screen.frame.width - 32)
        let natural = spaces.map { min(appearance.fontSize * 14.55, max(appearance.fontSize * 6.73, ($0.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: appearance.fontSize, weight: .medium)]).width + max(36, appearance.fontSize * 2.6))) }
        let total = natural.reduce(0, +) + CGFloat(spaces.count - 1) * 4 + 8
        let width = min(total, maxWidth)
        let scale = min(1, (width - 8 - CGFloat(spaces.count - 1) * 4) / natural.reduce(0, +))
        scroll.frame = NSRect(x: 4, y: 3, width: width - 8, height: itemHeight)
        let ids = Set(spaces.map(\.id))
        for id in Array(buttons.keys) where !ids.contains(id) { buttons.removeValue(forKey: id)?.removeFromSuperview() }
        var x: CGFloat = 0
        for (i, space) in spaces.enumerated() {
            let button: SpaceButton
            if let existing = buttons[space.id] { button = existing; button.update(space) }
            else { button = SpaceButton(space: space, pick: pick, settings: settings); buttons[space.id] = button; button.surface = content; content.addSubview(button) }
            button.pick = pick; button.settings = settings
            button.frame = NSRect(x: x, y: 0, width: max(48, appearance.fontSize * 3, natural[i] * scale), height: itemHeight)
            x += button.frame.width + 4
        }
        content.frame = NSRect(x: 0, y: 0, width: max(width - 8, x - 4), height: itemHeight)
        let focus = spaces.first(where: \.focused).flatMap { buttons[$0.id] }
        content.select(focus?.frame.insetBy(dx: 0.5, dy: 1), animated: wasVisible)
        if let visible = spaces.first(where: \.visible).flatMap({ buttons[$0.id] }) { content.scrollToVisible(visible.frame) }
        let topInset = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - topInset - appearance.topOffset - height, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }
}
