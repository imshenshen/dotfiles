import AppKit
import LocalAuthentication
import Security

@MainActor
enum GIFCredentials {
  private static let service = "im.rime.inputmethod.Squirrel.GIFSearch"
  private static var readStatus: OSStatus = errSecItemNotFound
  private static func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
     kSecAttrAccount as String: account]
  }
  static func read(_ account: String) -> String? {
    readStatus = errSecInteractionNotAllowed
    var previousInteraction = DarwinBoolean(true)
    guard SecKeychainGetUserInteractionAllowed(&previousInteraction) == errSecSuccess,
          SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else { return nil }
    defer { _ = SecKeychainSetUserInteractionAllowed(previousInteraction.boolValue) }
    var request = query(account)
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    let context = LAContext(); context.interactionNotAllowed = true
    request[kSecUseAuthenticationContext as String] = context
    var item: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &item)
    readStatus = status
    guard status == errSecSuccess, let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
  static func save(_ value: String, account: String) throws {
    let request = query(account), data = Data(value.utf8)
    var access: SecAccess?
    let accessStatus = SecAccessCreate("鼠须管 GIF 搜索" as CFString, nil, &access)
    guard accessStatus == errSecSuccess, let access else { throw CredentialError.storage(accessStatus) }
    let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrAccess as String: access]
    let status = SecItemUpdate(request as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var addition = request
      addition[kSecValueData as String] = data
      addition[kSecAttrAccess as String] = access
      let added = SecItemAdd(addition as CFDictionary, nil)
      guard added == errSecSuccess else { throw CredentialError.storage(added) }
    } else if status != errSecSuccess { throw CredentialError.storage(status) }
    guard read(account) == value else { throw CredentialError.readBack(readStatus) }
  }
  static func remove(_ account: String) throws {
    let status = SecItemDelete(query(account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw CredentialError.storage(status) }
  }
  enum CredentialError: LocalizedError {
    case storage(OSStatus), readBack(OSStatus)
    var errorDescription: String? {
      switch self {
      case .storage(let status): return "钥匙串保存失败（\(status)），请完成系统认证后重试。"
      case .readBack(let status): return "API Key 已写入，但当前鼠须管无法读取（\(status)）。请完成钥匙串认证后再次保存。"
      }
    }
  }
}

@MainActor
final class GIFPreferences: NSObject, NSWindowDelegate {
  static let shared = GIFPreferences()
  private var window: NSWindow?
  private let provider = NSPopUpButton()
  private let endpoint = NSTextField()
  private let key = NSSecureTextField()
  private let rating = NSPopUpButton()
  private let message = NSTextField(labelWithString: "")
  private let testButton = NSButton()
  private let spinner = NSProgressIndicator()
  private var testTask: Task<Void, Never>?

  func show() {
    if window == nil { create() }
    let current = GIFSettings.provider
    provider.selectItem(at: GIFProvider.allCases.firstIndex(of: current) ?? 0)
    endpoint.stringValue = GIFSettings.endpoint
    key.stringValue = ""
    key.placeholderString = GIFCredentials.read("apiKey") == nil ? "填写 API Key（自定义服务可留空）" : "已保存；留空保持原值"
    rating.selectItem(at: GIFRating.allCases.firstIndex(of: GIFSettings.rating) ?? 1)
    message.stringValue = "官方服务在中国大陆可能需要代理；自定义 endpoint 应返回与说明一致的 JSON。"
    updateEndpointHint()
    testButton.isEnabled = true
    window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window?.makeFirstResponder(provider.isEnabled ? key : provider)
  }

  private func create() {
    let window = VoiceEditingWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 560),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "GIF 搜索设置"
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    self.window = window
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: 560))
    window.contentView = root

    func label(_ title: String, _ y: CGFloat, width: CGFloat = 132) {
      let field = NSTextField(labelWithString: title)
      field.frame = NSRect(x: 24, y: y, width: width, height: 24)
      field.textColor = .labelColor; root.addSubview(field)
    }
    let intro = NSTextField(labelWithString: "选择 GIF 服务。Key 只保存在本机钥匙串，不会写入日志或输入法配置。")
    intro.frame = NSRect(x: 24, y: 512, width: 532, height: 22)
    intro.font = .systemFont(ofSize: 11); intro.textColor = .secondaryLabelColor
    root.addSubview(intro)

    label("服务", 466)
    provider.frame = NSRect(x: 168, y: 462, width: 388, height: 30)
    provider.addItems(withTitles: GIFProvider.allCases.map(\.title))
    provider.target = self; provider.action = #selector(providerChanged)
    root.addSubview(provider)

    label("Endpoint", 417)
    endpoint.frame = NSRect(x: 168, y: 413, width: 388, height: 28)
    endpoint.placeholderString = "留空使用官方地址"
    root.addSubview(endpoint)

    label("API Key", 368)
    key.frame = NSRect(x: 168, y: 364, width: 388, height: 28)
    root.addSubview(key)

    label("内容分级", 316)
    rating.frame = NSRect(x: 168, y: 312, width: 180, height: 30)
    rating.addItems(withTitles: GIFRating.allCases.map(\.title))
    root.addSubview(rating)

    let disclosure = NSTextField(labelWithString: "搜索词会发送到所选服务。GIF 仅复制到剪贴板，不会自动粘贴；关闭面板不会改变当前输入框焦点。")
    disclosure.frame = NSRect(x: 24, y: 266, width: 532, height: 34)
    disclosure.font = .systemFont(ofSize: 11); disclosure.textColor = .secondaryLabelColor
    disclosure.lineBreakMode = .byWordWrapping; disclosure.maximumNumberOfLines = 2
    root.addSubview(disclosure)

    message.frame = NSRect(x: 24, y: 218, width: 532, height: 40)
    message.font = .systemFont(ofSize: 11)
    message.textColor = .secondaryLabelColor
    message.lineBreakMode = .byWordWrapping; message.maximumNumberOfLines = 2
    root.addSubview(message)

    testButton.title = "测试连接"
    testButton.frame = NSRect(x: 24, y: 174, width: 112, height: 32)
    testButton.bezelStyle = .rounded
    testButton.target = self; testButton.action = #selector(testConnection)
    root.addSubview(testButton)

    spinner.style = .spinning; spinner.controlSize = .small
    spinner.isIndeterminate = true; spinner.isDisplayedWhenStopped = false
    spinner.frame = NSRect(x: 146, y: 182, width: 18, height: 18)
    root.addSubview(spinner)

    let note = NSTextField(labelWithString: "自定义 GET 参数：q、limit=24、offset；响应 items / next_offset / has_more。")
    note.frame = NSRect(x: 24, y: 142, width: 532, height: 22)
    note.font = .systemFont(ofSize: 10); note.textColor = .tertiaryLabelColor
    root.addSubview(note)

    let clear = NSButton(title: "删除 Key", target: self, action: #selector(clearKey))
    clear.frame = NSRect(x: 24, y: 24, width: 112, height: 32)
    clear.bezelStyle = .rounded; root.addSubview(clear)
    let save = NSButton(title: "保存", target: self, action: #selector(save))
    save.frame = NSRect(x: 444, y: 24, width: 112, height: 32)
    save.bezelStyle = .rounded; save.keyEquivalent = "\r"; root.addSubview(save)
  }

  private func selectedProvider() -> GIFProvider {
    GIFProvider.allCases[provider.indexOfSelectedItem]
  }
  private func selectedRating() -> GIFRating {
    GIFRating.allCases[max(0, rating.indexOfSelectedItem)]
  }

  @objc private func providerChanged() { updateEndpointHint() }

  private func updateEndpointHint() {
    switch selectedProvider() {
    case .giphy: endpoint.placeholderString = "https://api.giphy.com/v1/gifs/search（可填代理）"
    case .tenor: endpoint.placeholderString = "https://tenor.googleapis.com/v2/search（可填代理）"
    case .custom: endpoint.placeholderString = "https://example.com/gif-search（必填）"
    }
  }

  private func validated() -> (GIFProvider, String, String, GIFRating)? {
    let provider = selectedProvider()
    let endpointValue = endpoint.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let keyValue = key.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    if provider == .custom && endpointValue.isEmpty {
      message.stringValue = "自定义服务必须填写 HTTPS endpoint。"; return nil
    }
    if !endpointValue.isEmpty {
      guard let url = URL(string: endpointValue), GIFSearchService.isSafeHTTPS(url) else {
        message.stringValue = "Endpoint 必须是 HTTPS 公网地址。"; return nil
      }
    }
    if provider.keyRequired && keyValue.isEmpty && GIFCredentials.read("apiKey") == nil {
      message.stringValue = "\(provider.title) 需要 API Key。"; return nil
    }
    return (provider, endpointValue, keyValue, selectedRating())
  }

  @objc private func save() {
    guard let (provider, endpointValue, keyValue, rating) = validated() else { return }
    do {
      if !keyValue.isEmpty { try GIFCredentials.save(keyValue, account: "apiKey") }
      GIFSettings.save(provider: provider, endpoint: endpointValue, rating: rating)
      key.stringValue = ""
      key.placeholderString = "已保存；留空保持原值"
      message.stringValue = "已保存。再次输入 /gif 即可搜索。"
      RimeSlashUI.configurationChanged()
    } catch { message.stringValue = error.localizedDescription }
  }

  @objc private func clearKey() {
    do {
      try GIFCredentials.remove("apiKey")
      key.stringValue = ""; key.placeholderString = "填写 API Key（自定义服务可留空）"
      message.stringValue = "已删除本机 GIF API Key。"
    } catch { message.stringValue = error.localizedDescription }
  }

  @objc private func testConnection() {
    guard let (provider, endpointValue, enteredKey, rating) = validated() else { return }
    let keyValue = enteredKey.isEmpty ? (GIFCredentials.read("apiKey") ?? "") : enteredKey
    testTask?.cancel()
    testButton.isEnabled = false
    spinner.startAnimation(nil)
    message.stringValue = "正在连接…"
    testTask = Task { @MainActor [weak self] in
      defer {
        self?.spinner.stopAnimation(nil)
        self?.testButton.isEnabled = true
      }
      do {
        let service = try GIFSearchService(provider: provider, endpoint: endpointValue,
                                           key: keyValue, rating: rating)
        let page = try await service.search("hello")
        guard !Task.isCancelled else { return }
        self?.message.stringValue = "连接成功，返回 \(page.items.count) 条。"
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        self?.message.stringValue = error.localizedDescription
      }
    }
  }

  func windowWillClose(_ notification: Notification) {
    testTask?.cancel(); testTask = nil
    spinner.stopAnimation(nil)
    key.stringValue = ""
  }
}
