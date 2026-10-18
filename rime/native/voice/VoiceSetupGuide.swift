import AppKit

// Keep the application steps visible beside the credential fields. Each service
// has its own official console/key and must not silently reuse the other's key.
@MainActor final class VoiceSetupGuide: NSView {
  enum Service {
    case speech, rewrite
    var steps: String {
      switch self {
      case .speech: return """
      1. 登录火山引擎，按提示完成实名认证。
      2. 在豆包语音的“开通管理 / API 服务中心”开通流式语音识别 2.0，计费方式与下方选择一致。
      3. 在同一项目的“API Key 管理 / API 管理”创建 Key，复制到下方保存。
      新版 Key 无需 App ID；旧版凭证请切换旧控制台，在应用中获取 App ID 和 Access Token。
      """
      case .rewrite: return """
      1. 登录火山方舟，选择北京地域和目标项目。
      2. 在“开通管理”开通豆包文本模型（可选 Seed 2.1 Lite）；带“深度思考”标签也可以，本程序会关闭思考。
      3. 在“API Key 管理”创建 Key；从模型详情或调用示例复制 model 的值（Model ID），也可用同项目 ep- 接入点 ID。
      4. 将两项填入下方保存。方舟与语音分别开通、分别创建 Key。
      """
      }
    }
    var keyURL: URL {
      switch self {
      case .speech: return URL(string: "https://console.volcengine.com/speech/new/setting/apikeys?projectName=default")!
      case .rewrite: return URL(string: "https://ark.volcengine.com/region:cn-beijing/apikey")!
      }
    }
    var guideURL: URL {
      switch self {
      case .speech: return URL(string: "https://docs.volcengine.com/docs/DoubaoVoice/QuickStartNewConsole?lang=zh")!
      case .rewrite: return URL(string: "https://docs.volcengine.com/docs/ark/quick-start?lang=zh")!
      }
    }
  }
  private let service: Service
  init(service: Service, frame: NSRect) {
    self.service = service
    super.init(frame: frame)
    wantsLayer = true; layer?.cornerRadius = 10
    layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
    let title = NSTextField(labelWithString: "如何申请与填写")
    title.font = .boldSystemFont(ofSize: 13)
    title.frame = NSRect(x: 12, y: 188, width: frame.width-24, height: 22); addSubview(title)
    let steps = NSTextField(wrappingLabelWithString: service.steps)
    steps.font = .systemFont(ofSize: 12); steps.textColor = .secondaryLabelColor
    steps.frame = NSRect(x: 12, y: 52, width: frame.width-24, height: 132); addSubview(steps)
    let titles = service == .speech ? ["申请语音 API Key ↗", "开通与接入指南 ↗"] : ["申请方舟 API Key ↗", "开通模型与接入指南 ↗"]
    for (index, text) in titles.enumerated() {
      let button = NSButton(title: text, target: self, action: #selector(openLink(_:)))
      button.tag = index; button.isBordered = false; button.alignment = .left
      button.attributedTitle = NSAttributedString(string: text, attributes: [.foregroundColor: NSColor.linkColor,
        .font: NSFont.systemFont(ofSize: 12), .underlineStyle: NSUnderlineStyle.single.rawValue])
      button.frame = NSRect(x: 12+CGFloat(index)*236, y: 12, width: 230, height: 28)
      button.toolTip = (index == 0 ? service.keyURL : service.guideURL).absoluteString
      addSubview(button)
    }
  }
  required init?(coder: NSCoder) { fatalError("init(coder:)") }
  @objc private func openLink(_ sender: NSButton) { NSWorkspace.shared.open(sender.tag == 0 ? service.keyURL : service.guideURL) }
}
