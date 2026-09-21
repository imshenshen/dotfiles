import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let client = YabaiClient(executable: YabaiClient.locate())
    private var status: NSStatusItem!
    private var panels: [UInt32: BarWindow] = [:]
    private var snapshot: Snapshot?
    private var refreshTask: Task<Void, Never>?
    private var debounce: Task<Void, Never>?
    private var pending = false
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var signalObserver: NSObjectProtocol?
    private var lastSignalCheck = Date.distantPast
    private var connected = false
    private var busy = false
    private var quitting = false
    private let appearance = AppearanceStore()
    private var settingsWindow: SettingsWindow?
    private var queuedFocus: Space?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        appearance.onChange = { [weak self] in self?.render() }
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: "SpaceBar")
        updateMenu(message: "正在连接 yabai…")
        signalObserver = DistributedNotificationCenter.default().addObserver(forName: notificationName, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.scheduleRefresh() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.render(); self?.scheduleRefresh() }
        })
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 5
        refresh()
    }
    private func scheduleRefresh() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 60_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
    @objc private func refreshNow() { refresh() }
    private func refresh() {
        guard !quitting else { return }
        if refreshTask != nil { pending = true; return }
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.refreshTask = nil
                if self.pending { self.pending = false; self.scheduleRefresh() }
            }
            do {
                let next = try await self.client.snapshot()
                guard !self.quitting else { return }
                let changed = self.snapshot != next || !self.connected
                self.snapshot = next; self.connected = true
                if changed { self.render() }
                self.updateMenu(message: "已连接 · \(next.spaces.count) 个 Space")
                if Date().timeIntervalSince(self.lastSignalCheck) > 60 {
                    do {
                        try await self.client.installSignals(helper: Bundle.main.executablePath ?? CommandLine.arguments[0])
                        self.lastSignalCheck = Date()
                    } catch {
                        self.updateMenu(message: "事件订阅失败（30 秒校准仍可用）", detail: error.localizedDescription)
                    }
                }
            } catch {
                self.connected = false; self.lastSignalCheck = .distantPast
                self.panels.values.forEach { $0.panel.orderOut(nil) }
                self.updateMenu(message: "yabai 未连接 · 点此菜单重试", detail: error.localizedDescription)
            }
        }
    }
    private func render() {
        guard let snapshot, connected else { return }
        let live = Set(NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
        for id in Array(panels.keys) where !live.contains(id) { panels.removeValue(forKey: id)?.panel.close() }
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            let bar = panels[id] ?? BarWindow(); panels[id] = bar
            bar.render(spaces: snapshot.spaces(on: id), screen: screen, appearance: appearance.value, settings: { [weak self] in self?.openSettings() }) { [weak self] space, rename in
                if rename { self?.rename(space) } else { self?.act(space) }
            }
        }
    }
    private func act(_ space: Space, name: String? = nil) {
        guard connected, !quitting else { return }
        if busy {
            if name == nil { queuedFocus = space }
            return
        }
        busy = true
        Task {
            defer {
                busy = false; refresh()
                if let next = queuedFocus { queuedFocus = nil; act(next) }
            }
            do { try await client.act(id: space.id, name: name) }
            catch { showError(error.localizedDescription) }
        }
    }
    private func rename(_ space: Space) {
        guard !busy, connected else { return }
        let alert = NSAlert()
        alert.messageText = "重命名 Space \(space.index)"
        alert.informativeText = "保存后同步到 yabai。按 Esc 取消。"
        let input = NSTextField(string: space.name)
        input.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        act(space, name: input.stringValue)
    }
    private func showError(_ message: String) {
        let alert = NSAlert(); alert.messageText = "操作未完成"; alert.informativeText = message
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
    private func updateMenu(message: String, detail: String? = nil) {
        status.button?.toolTip = detail ?? message
        let menu = NSMenu()
        let info = NSMenuItem(title: message, action: nil, keyEquivalent: ""); info.isEnabled = false; menu.addItem(info)
        menu.addItem(.separator())
        func add(_ title: String, _ action: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        add("设置…", #selector(openSettings), key: ",")
        add("立即刷新", #selector(refreshNow))
        add("下移 4 pt", #selector(moveDown)); add("上移 4 pt", #selector(moveUp))
        add("恢复默认位置", #selector(resetOffset))
        menu.addItem(.separator()); add("退出 SpaceBar", #selector(quit), key: "q")
        status.menu = menu
    }
    @objc private func openSettings() {
        if settingsWindow == nil { settingsWindow = SettingsWindow(store: appearance) }
        settingsWindow?.present()
    }
    @objc private func moveDown() { appearance.value.topOffset = min(160, appearance.value.topOffset + 4); settingsWindow?.sync() }
    @objc private func moveUp() { appearance.value.topOffset = max(0, appearance.value.topOffset - 4); settingsWindow?.sync() }
    @objc private func resetOffset() { appearance.value.topOffset = 8; settingsWindow?.sync() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true; timer?.invalidate(); debounce?.cancel()
        Task {
            // Wait for registration in flight before removing our own signals.
            await refreshTask?.value
            await client.removeSignals()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
