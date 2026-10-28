import AppKit
import Carbon
import InputMethodKit

@MainActor
public final class RimeSlashController {
  private let clientProvider: () -> IMKTextInput?
  private let commitText: (String) -> Bool
  private let hideCandidates: () -> Void
  private let unmarkClient: () -> Void
  private let caretRect: () -> NSRect
  private let asciiMode: () -> Bool

  public init(client: @escaping () -> IMKTextInput?, commit: @escaping (String) -> Bool,
              hideCandidates: @escaping () -> Void, unmark: @escaping () -> Void,
              caretRect: @escaping () -> NSRect, asciiMode: @escaping () -> Bool) {
    clientProvider = client
    commitText = commit
    self.hideCandidates = hideCandidates
    unmarkClient = unmark
    self.caretRect = caretRect
    self.asciiMode = asciiMode
  }

  public var isPresenting: Bool { SlashSession.shared.isPresenting(owner: self) }

  public func activate() {
    // The panel belongs to whichever input controller most recently opened it.
  }

  public func deactivate() {
    SlashSession.shared.dismissIfOwner(self)
  }

  public func handle(_ event: NSEvent) -> Bool {
    SlashSession.shared.handle(event, owner: self)
  }

  @discardableResult
  public func present(_ command: RimeSlashCommand) -> Bool {
    SlashSession.shared.present(command, owner: self)
  }

  /// Called after Rime has processed a key. The exact raw input decides whether
  /// this is the palette trigger, so ordinary "/" and every other symbol
  /// category continue to behave exactly as before.
  @discardableResult
  public func capture(input: String) -> Bool {
    guard let command = SlashCommandMatch.match(input: input, asciiMode: asciiMode()) else { return false }
    return SlashSession.shared.present(command, owner: self)
  }

  var hasClient: Bool { clientProvider() != nil }
  var isASCIIMode: Bool { asciiMode() }
  func prepareForPalette() {
    unmarkClient()
    hideCandidates()
  }
  func commitGlyph(_ glyph: String) -> Bool { commitText(glyph) }
  func caretAnchor() -> NSRect? {
    let rect = caretRect()
    return rect.isEmpty ? nil : rect
  }
}

@MainActor
public enum RimeSlashUI {
  public static func startServices() { SlashSession.shared.startServices() }
  public static func openGIFSettings() { SlashSession.shared.openSettings() }
  public static func dismissForVoice() { SlashSession.shared.dismissIfPresenting() }
  public static func configurationChanged() { SlashSession.shared.configurationChanged() }
}

@MainActor
final class SlashSession {
  static let shared = SlashSession()
  private weak var owner: RimeSlashController?
  private var panel: SlashPaletteWindow?
  private var state: SlashPaletteState?
  private var symbols: [SlashSymbol] = []
  private var categories: [String] = []
  private var gifs: [GIFItem] = []
  private var nextCursor: String?
  private var message: String?
  private var loading = false
  private var provider: GIFProvider = .giphy
  private var searchTask: Task<Void, Never>?
  private var copyTask: Task<Void, Never>?
  private var closeTask: Task<Void, Never>?
  private var generation = UUID()
  private var started = false
  private var settingsObserver: NSObjectProtocol?
  private var workspaceObserver: NSObjectProtocol?

  var isPresenting: Bool { panel?.isVisible == true }

  func isPresenting(owner: RimeSlashController) -> Bool {
    panel?.isVisible == true && self.owner === owner
  }

  func startServices() {
    guard !started else { return }
    started = true
    DispatchQueue.global(qos: .utility).async { _ = GIFClipboard.cleanup() }
    settingsObserver = DistributedNotificationCenter.default().addObserver(
      forName: .init("SquirrelGIFSettingsNotification"), object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { SlashSession.shared.openSettings() }
    }
    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { _ in
      MainActor.assumeIsolated { SlashSession.shared.dismissIfPresenting() }
    }
  }

  func present(_ command: RimeSlashCommand, owner: RimeSlashController) -> Bool {
    guard !VoiceSession.shared.active, !owner.isASCIIMode, owner.hasClient else { return false }
    guard let panel = ensurePanel() else { return false }
    owner.prepareForPalette()
    closeTask?.cancel(); closeTask = nil
    searchTask?.cancel(); searchTask = nil
    copyTask?.cancel(); copyTask = nil
    generation = UUID()
    self.owner = owner
    var fresh = SlashPaletteState(kind: command)
    fresh.columns = SlashPaletteCanvas.columns
    fresh.pageRows = SlashPaletteCanvas.rows
    state = fresh
    symbols = []
    gifs = []
    nextCursor = nil
    loading = false
    message = nil
    provider = GIFSettings.provider
    if command == .symbols {
      categories = SlashSymbolIndex.shared.categories
      refreshSymbols(resetSelection: true)
    } else {
      categories = []
      if IsSecureEventInputEnabled() {
        message = "安全输入模式下不会搜索 GIF。"
      } else if fresh.query.isEmpty {
        message = "输入英文关键词搜索 GIF。"
      }
      updateSnapshot()
    }
    panel.present(anchor: ownerCaretRect())
    return true
  }

  func dismissIfPresenting() {
    guard panel?.isVisible == true else { return }
    dismiss()
  }

  func dismissIfOwner(_ controller: RimeSlashController) {
    guard owner === controller else { return }
    dismiss()
  }

  func dismiss() {
    searchTask?.cancel(); searchTask = nil
    copyTask?.cancel(); copyTask = nil
    closeTask?.cancel(); closeTask = nil
    generation = UUID()
    panel?.orderOut(nil)
    state = nil
    symbols = []
    gifs = []
    categories = []
    nextCursor = nil
    message = nil
    loading = false
    owner = nil
  }

  func openSettings() {
    dismiss()
    GIFPreferences.shared.show()
  }

  func configurationChanged() {
    guard let state, state.kind == .gif, panel?.isVisible == true else { return }
    provider = GIFSettings.provider
    self.state?.selection = 0
    gifs = []
    nextCursor = nil
    message = nil
    loading = false
    updateSnapshot()
    startGIFSearch(delay: 0)
  }

  func handle(_ event: NSEvent, owner: RimeSlashController) -> Bool {
    guard isPresenting(owner: owner), state != nil else { return false }
    switch event.type {
    case .flagsChanged:
      return true
    case .keyDown:
      let blocked = event.modifierFlags.intersection([.command, .control, .option])
      guard blocked.isEmpty else { return false }
      switch event.keyCode {
      case 53:
        if self.state?.escape() == true { dismiss() } else { queryDidChange() }
      case 51, 117:
        if self.state?.backspace() == true { dismiss() } else { queryDidChange() }
      case 36, 76:
        activateSelection()
      case 123:
        move(dx: -1, dy: 0)
      case 124:
        move(dx: 1, dy: 0)
      case 125:
        move(dx: 0, dy: 1)
      case 126:
        move(dx: 0, dy: -1)
      case 48:
        cycleCategory(backwards: event.modifierFlags.contains(.shift))
      case 116:
        page(up: true)
      case 121:
        page(up: false)
      case 115:
        jumpTo(0)
      case 119:
        jumpTo(max(0, (self.state?.itemCount ?? 0) - 1))
      default:
        guard let characters = event.characters, characters.count == 1,
              let scalar = characters.unicodeScalars.first, (32...126).contains(scalar.value) else {
          return true
        }
        let value = characters.lowercased()
        guard self.state?.append(value) == true else { return true }
        queryDidChange()
      }
      return true
    default:
      return false
    }
  }

  private func ensurePanel() -> SlashPaletteWindow? {
    if let panel { return panel }
    let created = SlashPaletteWindow()
    created.canvas.imageProvider = { item in GIFImageLoader.shared.cached(item.thumbnailURL) }
    created.canvas.onCategory = { [weak self] category in self?.chooseCategory(category) }
    created.canvas.onActivate = { [weak self] index in self?.activate(index: index) }
    created.canvas.onSettings = { [weak self] in self?.openSettings() }
    created.canvas.onScroll = { [weak self] delta in self?.scroll(delta) }
    panel = created
    return created
  }

  private func ownerCaretRect() -> NSRect? {
    // The controller is deliberately not consulted for focus. The anchor is
    // read-only geometry; a missing anchor falls back to the pointer.
    guard let owner else { return nil }
    return owner.caretAnchor()
  }

  private func updateSnapshot() {
    guard let state, let panel else { return }
    var snapshot = SlashPaletteSnapshot(kind: state.kind)
    snapshot.query = state.query
    snapshot.categories = categories
    snapshot.selectedCategory = state.category
    snapshot.symbols = symbols
    snapshot.gifs = gifs
    snapshot.selection = state.selection
    snapshot.pageStart = state.pageStart
    snapshot.pageCount = state.pageCount
    snapshot.itemCount = state.itemCount
    snapshot.message = message
    snapshot.loading = loading
    snapshot.provider = state.kind == .gif ? provider.title : nil
    panel.canvas.snapshot = snapshot
    panel.canvas.window?.invalidateCursorRects(for: panel.canvas)
    loadVisibleThumbnails()
  }

  private func loadVisibleThumbnails() {
    guard let state, state.kind == .gif else { return }
    let end = min(gifs.count, state.pageStart + SlashPaletteCanvas.pageSize)
    guard state.pageStart < end else { return }
    for item in gifs[state.pageStart..<end] {
      GIFImageLoader.shared.load(item.thumbnailURL) { [weak self] _ in
        self?.panel?.canvas.needsDisplay = true
      }
    }
  }

  private func queryDidChange() {
    guard let state else { return }
    if state.kind == .symbols {
      refreshSymbols(resetSelection: true)
    } else {
      searchTask?.cancel(); searchTask = nil
      generation = UUID()
      gifs = []
      nextCursor = nil
      loading = false
      self.state?.setItemCount(0)
      message = state.query.isEmpty ? "输入英文关键词搜索 GIF。" : "输入完成后自动搜索…"
      updateSnapshot()
      if !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        startGIFSearch(delay: 300_000_000)
      }
    }
  }

  private func refreshSymbols(resetSelection: Bool) {
    guard let state, state.kind == .symbols else { return }
    symbols = SlashSymbolIndex.shared.search(state.query, category: state.category)
    if resetSelection { self.state?.selection = 0 }
    self.state?.setItemCount(symbols.count)
    message = symbols.isEmpty ? "没有匹配的符号。试试拼音、英文或 Unicode 名称。" : nil
    loading = false
    updateSnapshot()
  }

  private func chooseCategory(_ category: String) {
    guard let state, state.kind == .symbols else { return }
    self.state?.selectCategory(category)
    refreshSymbols(resetSelection: true)
  }

  private func cycleCategory(backwards: Bool) {
    guard let state, state.kind == .symbols, !categories.isEmpty else { return }
    self.state?.cycleCategory(categories, backwards: backwards)
    refreshSymbols(resetSelection: true)
  }

  private func move(dx: Int, dy: Int) {
    guard let state else { return }
    self.state?.move(dx: dx, dy: dy)
    updateSnapshot()
    if state.kind == .gif { loadMoreIfAtEnd() }
  }

  private func page(up: Bool) {
    guard let state else { return }
    self.state?.page(up: up)
    updateSnapshot()
    if state.kind == .gif, !up { loadMoreIfAtEnd() }
  }

  private func scroll(_ deltaRows: Int) {
    guard let state else { return }
    self.state?.move(dx: 0, dy: deltaRows)
    updateSnapshot()
    if state.kind == .gif, deltaRows > 0 { loadMoreIfAtEnd() }
  }

  private func jumpTo(_ index: Int) {
    guard let state else { return }
    let last = max(0, state.itemCount - 1)
    self.state?.selection = min(max(0, index), last)
    updateSnapshot()
    if state.kind == .gif { loadMoreIfAtEnd() }
  }

  private func activate(index: Int) {
    guard state != nil else { return }
    self.state?.selection = index
    self.state?.clampSelection()
    updateSnapshot()
    activateSelection()
  }

  private func activateSelection() {
    guard let state, let index = state.selectedIndex else { return }
    switch state.kind {
    case .symbols:
      guard index < symbols.count, let owner else { return }
      let glyph = symbols[index].glyph
      if owner.commitGlyph(glyph) {
        dismiss()
      } else {
        message = "目标输入框不可用，面板已保留。"
        updateSnapshot()
      }
    case .gif:
      guard index < gifs.count else { return }
      copyGIF(gifs[index])
    }
  }

  private func copyGIF(_ item: GIFItem) {
    guard copyTask == nil else { return }
    message = "正在下载 GIF…"
    updateSnapshot()
    copyTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        _ = try await GIFClipboard.copy(item: item)
        guard !Task.isCancelled, self.panel?.isVisible == true else { return }
        self.message = "已复制 GIF；回到输入框按 ⌘V 粘贴。"
        self.copyTask = nil
        self.updateSnapshot()
        self.closeTask?.cancel()
        self.closeTask = Task { @MainActor [weak self] in
          try? await Task.sleep(nanoseconds: 1_100_000_000)
          guard !Task.isCancelled else { return }
          self?.dismiss()
        }
      } catch is CancellationError {
        self.copyTask = nil
      } catch {
        guard !Task.isCancelled else { self.copyTask = nil; return }
        self.message = error.localizedDescription
        self.copyTask = nil
        self.updateSnapshot()
      }
    }
  }

  private func startGIFSearch(delay: UInt64) {
    guard let state, state.kind == .gif else { return }
    guard !IsSecureEventInputEnabled() else {
      loading = false
      message = "安全输入模式下不会搜索 GIF。"
      updateSnapshot()
      return
    }
    let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    searchTask?.cancel()
    let token = UUID()
    generation = token
    if delay == 0 {
      loading = true
      message = nil
      updateSnapshot()
    }
    searchTask = Task { @MainActor [weak self] in
      if delay > 0 {
        try? await Task.sleep(nanoseconds: delay)
      }
      guard !Task.isCancelled, let self, self.generation == token,
            self.state?.kind == .gif,
            self.state?.query.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
      self.loading = true
      self.message = nil
      self.updateSnapshot()
      await self.performGIFSearch(query: query, cursor: nil, append: false, token: token)
    }
  }

  private func performGIFSearch(query: String, cursor: String?, append: Bool, token: UUID) async {
    guard !IsSecureEventInputEnabled() else {
      loading = false
      message = "安全输入模式下不会搜索 GIF。"
      updateSnapshot()
      return
    }
    do {
      let key = GIFCredentials.read("apiKey") ?? ""
      let service = try GIFSearchService(provider: GIFSettings.provider, endpoint: GIFSettings.endpoint,
                                         key: key, rating: GIFSettings.rating)
      let page = try await service.search(query, cursor: cursor)
      guard !Task.isCancelled, generation == token, let state, state.kind == .gif,
            state.query.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }
      provider = service.provider
      let oldCount = gifs.count
      let wasAtEnd = oldCount == 0 || (self.state?.selection ?? 0) >= oldCount - 1
      if append {
        var seen = Set(gifs.map(\.id))
        for item in page.items where seen.insert(item.id).inserted { gifs.append(item) }
      } else {
        gifs = page.items
        self.state?.selection = 0
      }
      nextCursor = page.next
      loading = false
      searchTask = nil
      if gifs.isEmpty {
        message = "没有找到 GIF，试试其他英文关键词。"
      } else if append && page.items.isEmpty {
        message = "没有更多结果。"
      } else {
        message = nil
      }
      self.state?.setItemCount(gifs.count)
      if append, wasAtEnd, oldCount > 0, gifs.count > oldCount {
        self.state?.selection = oldCount
      }
      self.state?.clampSelection()
      updateSnapshot()
    } catch is CancellationError {
      return
    } catch {
      guard !Task.isCancelled, generation == token else { return }
      loading = false
      searchTask = nil
      message = error.localizedDescription
      updateSnapshot()
    }
  }

  private func loadMoreIfAtEnd() {
    guard !IsSecureEventInputEnabled() else {
      loading = false
      message = "安全输入模式下不会搜索 GIF。"
      updateSnapshot()
      return
    }
    guard let state, state.kind == .gif, !loading, searchTask == nil,
          let cursor = nextCursor, !cursor.isEmpty,
          state.itemCount > 0, state.selection >= state.itemCount - 1 else { return }
    let query = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return }
    let token = UUID()
    generation = token
    loading = true
    message = nil
    updateSnapshot()
    searchTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.performGIFSearch(query: query, cursor: cursor, append: true, token: token)
    }
  }
}
