import AppKit

private final class SettingsPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command && event.charactersIgnoringModifiers == "w" {
            performClose(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class SettingsWindow: NSWindowController, NSWindowDelegate {
    private let store: AppearanceStore
    private var wells: [NSColorWell] = []
    private var sliders: [NSSlider] = []
    private var values: [NSTextField] = []
    private var animationButton: NSButton!
    private let colorPaths: [WritableKeyPath<Appearance, RGBA>] = [\.background, \.inactive, \.selection, \.text, \.selectedText]
    init(store: AppearanceStore) {
        self.store = store
        let window = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 530), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "SpaceBar 设置"; window.isReleasedWhenClosed = false
        window.isFloatingPanel = true; window.hidesOnDeactivate = false
        super.init(window: window)
        window.delegate = self
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        let subtitle = NSTextField(labelWithString: "修改即时生效，并自动保存。")
        subtitle.textColor = .secondaryLabelColor; stack.addArrangedSubview(subtitle)
        for (i, label) in ["工具条背景", "未选中标签", "滑动选中背景", "普通文字", "选中文字"].enumerated() {
            let well = NSColorWell(); well.tag = i; well.target = self; well.action = #selector(colorChanged(_:))
            well.widthAnchor.constraint(equalToConstant: 54).isActive = true
            well.heightAnchor.constraint(equalToConstant: 25).isActive = true
            wells.append(well); stack.addArrangedSubview(row(label, control: well))
        }
        animationButton = NSButton(checkboxWithTitle: "启用液态滑动动画", target: self, action: #selector(animationChanged))
        stack.addArrangedSubview(animationButton)
        for (i, spec) in [("动画速度", 0.4, 2.5), ("背景圆角", 0.0, 32.0), ("距菜单栏下沿", 0.0, 160.0), ("工具条高度", 22.0, 64.0), ("文字大小", 9.0, 24.0)].enumerated() {
            let slider = NSSlider(value: 0, minValue: spec.1, maxValue: spec.2, target: self, action: #selector(sliderChanged(_:)))
            slider.tag = i; slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 155).isActive = true
            let value = NSTextField(labelWithString: "")
            value.alignment = .right; value.widthAnchor.constraint(equalToConstant: 54).isActive = true
            let controls = NSStackView(views: [slider, value]); controls.spacing = 8
            sliders.append(slider); values.append(value)
            stack.addArrangedSubview(row(spec.0, control: controls))
        }
        let reset = NSButton(title: "恢复默认设置", target: self, action: #selector(reset))
        stack.addArrangedSubview(reset)
        let note = NSTextField(wrappingLabelWithString: "系统开启“减少动态效果”时，将自动关闭滑动动画。")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        note.widthAnchor.constraint(equalToConstant: 370).isActive = true; stack.addArrangedSubview(note)
        sync(); window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func row(_ label: String, control: NSView) -> NSStackView {
        let text = NSTextField(labelWithString: label); text.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let row = NSStackView(views: [text, control]); row.spacing = 8; return row
    }
    func present() {
        sync(); NSApp.activate(ignoringOtherApps: true); showWindow(nil); window?.makeKeyAndOrderFront(nil)
    }
    func sync() {
        for (i, well) in wells.enumerated() { well.color = store.value[keyPath: colorPaths[i]].color }
        animationButton.state = store.value.animation ? .on : .off
        let numbers = [store.value.speed, store.value.radius, store.value.topOffset, store.value.effectiveHeight, store.value.fontSize]
        for (i, slider) in sliders.enumerated() { slider.doubleValue = numbers[i] }
        values[0].stringValue = String(format: "%.1f×", store.value.speed)
        values[1].stringValue = String(format: "%.0f pt", store.value.radius)
        values[2].stringValue = String(format: "%.0f pt", store.value.topOffset)
        values[3].stringValue = String(format: "%.0f pt", store.value.effectiveHeight)
        values[4].stringValue = String(format: "%.0f pt", store.value.fontSize)
        sliders[3].minValue = store.value.minimumHeight
        sliders[0].isEnabled = store.value.animation
    }
    @objc private func colorChanged(_ sender: NSColorWell) { store.value[keyPath: colorPaths[sender.tag]] = RGBA(color: sender.color) }
    @objc private func animationChanged() { store.value.animation = animationButton.state == .on; sync() }
    @objc private func sliderChanged(_ sender: NSSlider) {
        switch sender.tag {
        case 0: store.value.speed = sender.doubleValue
        case 1: store.value.radius = sender.doubleValue.rounded()
        case 2: store.value.topOffset = sender.doubleValue.rounded()
        case 3: store.value.height = max(store.value.minimumHeight, sender.doubleValue.rounded())
        default:
            var value = store.value
            value.fontSize = sender.doubleValue.rounded()
            value.height = max(value.height, value.minimumHeight)
            store.value = value
        }
        sync()
    }
    @objc private func reset() { store.reset(); sync() }
    func windowWillClose(_ notification: Notification) { wells.forEach { $0.deactivate() }; NSColorPanel.shared.orderOut(nil) }
}
