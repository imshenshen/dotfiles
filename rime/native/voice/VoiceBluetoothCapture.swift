import AVFoundation
import CoreMedia

// Bluetooth microphones negotiate capture formats when opened. Let AVFoundation
// own that negotiation instead of binding an AVAudioEngine input to an output graph.
final class VoiceBluetoothCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
  static let format = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
  private let session = AVCaptureSession()
  private let output = AVCaptureAudioDataOutput()
  private let queue = DispatchQueue(label: "im.rime.bluetooth.capture")
  private let uid: String
  private let name: String
  private var converter: AVAudioConverter?
  private var sourceFormat: AVAudioFormat?
  private var active = false
  private var received = false
  private var observer: NSObjectProtocol?
  private var disconnectObserver: NSObjectProtocol?
  var onBuffer: ((AVAudioPCMBuffer) -> Void)?
  var onError: ((String) -> Void)?
  init(device: VoiceDevice) { uid = device.uid; name = device.name; super.init() }
  enum CaptureError: LocalizedError {
    case missing, unsupported, silent
    var errorDescription: String? {
      switch self {
      case .missing: return "无法连接所选蓝牙麦克风，请确认耳机已连接并刷新设备列表。"
      case .unsupported: return "无法启动所选蓝牙麦克风的音频采集。"
      case .silent: return "蓝牙麦克风没有传来音频，请检查连接后重新测试。"
      }
    }
  }
  func start() async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      queue.async {
        do {
          let devices = AVCaptureDevice.devices(for: .audio)
          let byName = devices.filter { $0.localizedName == self.name }
          guard let device = devices.first(where: { $0.uniqueID == self.uid }) ?? (byName.count == 1 ? byName.first : nil) else { throw CaptureError.missing }
          let input = try AVCaptureDeviceInput(device: device)
          let selectedUID = device.uniqueID
          self.session.beginConfiguration()
          guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
            self.session.commitConfiguration(); throw CaptureError.unsupported
          }
          self.session.addInput(input)
          self.session.addOutput(self.output)
          self.output.setSampleBufferDelegate(self, queue: self.queue)
          self.session.commitConfiguration()
          self.active = true
          self.observer = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: self.session, queue: nil) { [weak self] notification in
            let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? Error)?.localizedDescription ?? "蓝牙麦克风采集失败。"
            self?.queue.async { [weak self] in self?.fail(message) }
          }
          self.disconnectObserver = NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: nil) { [weak self] notification in
            guard let disconnected = notification.object as? AVCaptureDevice, disconnected.uniqueID == selectedUID else { return }
            self?.queue.async { [weak self] in self?.fail("所选蓝牙麦克风已断开，请重新连接后测试。") }
          }
          self.session.startRunning()
          guard self.session.isRunning else { throw CaptureError.unsupported }
          continuation.resume()
          self.queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.active, !self.received else { return }
            self.fail(CaptureError.silent.localizedDescription)
          }
        } catch { continuation.resume(throwing: error) }
      }
    }
  }
  func stop() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      queue.async {
        self.active = false
        self.output.setSampleBufferDelegate(nil, queue: nil)
        if let observer = self.observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        if let observer = self.disconnectObserver { NotificationCenter.default.removeObserver(observer); self.disconnectObserver = nil }
        if self.session.isRunning { self.session.stopRunning() }
        continuation.resume()
      }
    }
  }
  private func fail(_ message: String) {
    guard active else { return }; active = false; onError?(message)
  }
  static func pcmBuffer(_ sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let description = CMSampleBufferGetFormatDescription(sample),
          CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio else { return nil }
    let format = AVAudioFormat(cmAudioFormatDescription: description)
    let frames = CMSampleBufferGetNumSamples(sample)
    guard frames > 0, frames <= Int(Int32.max), format.sampleRate.isFinite, format.sampleRate > 0,
          format.channelCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else { return nil }
    buffer.frameLength = AVAudioFrameCount(frames)
    guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else { return nil }
    return buffer
  }
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard active else { return }
    guard let input = Self.pcmBuffer(sampleBuffer) else { fail("无法读取蓝牙麦克风的音频格式。"); return }
    guard let result = normalize(input) else { fail("蓝牙麦克风音频转换失败。"); return }
    if result.frameLength > 0 { received = true; onBuffer?(result) }
  }
  // Called only on the serial capture queue; recreate converters on negotiated format changes.
  func normalize(_ input: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    if sourceFormat?.isEqual(input.format) != true {
      sourceFormat = input.format
      converter = AVAudioConverter(from: input.format, to: Self.format)
      converter?.channelMap = [0]
    }
    guard let converter else { return nil }
    let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * Self.format.sampleRate / input.format.sampleRate)) + 32
    guard let result = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: capacity) else { return nil }
    var supplied = false
    var error: NSError?
    let status = converter.convert(to: result, error: &error) { _, state in
      if supplied { state.pointee = .noDataNow; return nil }
      supplied = true; state.pointee = .haveData; return input
    }
    guard status != .error, error == nil else { return nil }
    return result
  }
}
