import AppKit
import AVFoundation
import Speech
import OSLog
import AudioToolbox

// Apple stays local; explicitly selected Doubao sends PCM over its fixed WSS endpoint.
@MainActor final class VoiceHelper: NSObject, NSApplicationDelegate {
  var session = ""
  var engine: AVAudioEngine?
  var bluetoothCapture: VoiceBluetoothCapture?
  private var finishAudio: (() -> Void)?
  var stopAnalysis: (() async -> Void)?
  var cancelAnalysis: (() async -> Void)?
  private var resultTask: Task<Void, Never>?
  var busy = false
  private var sequence: UInt64 = 0
  private var releaseModel: (() async -> Void)?
  private let logger = Logger(subsystem: "im.rime.inputmethod.Squirrel", category: "Voice")
  private var deviceUID = ""
  var inputChannel = 0
  private var deviceObserver: NSObjectProtocol?
  var cloud: DoubaoStream?
  var feedTask: Task<Void, Never>?

  func emit(_ type: String, _ fields: [String: Any] = [:]) {
    if type != "audio" { logger.info("Recognizer state: \(type, privacy: .public)") } // No transcript/audio.
    var event = fields
    event["type"] = type
    event["session"] = session
    sequence &+= 1
    event["sequence"] = sequence
    guard let data = try? JSONSerialization.data(withJSONObject: event) else { return }
    FileHandle.standardOutput.write(data + Data([10]))
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    let args = CommandLine.arguments
    if args.count == 3 && args[1] == "--transcribe" {
      session = "file-test"
      Task {
        do { try await transcribeFile(URL(fileURLWithPath: args[2])) }
        catch { await cancel(); emit("error", ["message": error.localizedDescription]) }
        NSApp.terminate(nil)
      }
      return
    }
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      while let line = readLine() {
        guard let data = line.data(using: .utf8),
              let command = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { continue }
        Task { @MainActor in await self?.command(command) }
      }
      Task { @MainActor in await self?.cancel(); NSApp.terminate(nil) }
    }
    emit("ready")
  }

  func command(_ command: [String: String]) async {
    switch command["action"] {
    case "start", "meter":
      guard !busy else { return }
      busy = true
      session = command["session"] ?? UUID().uuidString
      deviceUID = command["device"] ?? ""
      inputChannel = max(0, Int(command["channel"] ?? "0") ?? 0)
      do {
        if command["action"] == "meter" { try await startMeter() }
        else if command["provider"] == "doubao" { try await startCloud(command) }
        else if command["fixture"] == "/tmp/rime-voice-acceptance/speech.aiff" {
          try await startFixture(URL(fileURLWithPath: command["fixture"]!))
        } else { try await start() }
      }
      catch { await cancel(); emit("error", ["message": error.localizedDescription]) }
    case "stop": await stop()
    case "cancel": await cancel()
    case "quit": await cancel(); NSApp.terminate(nil)
    default: break
    }
  }

  enum VoiceError: LocalizedError {
    case system, model, microphone, format, device, channel
    var errorDescription: String? {
      switch self {
      case .system: return "本地语音需要 macOS 26 或更新版本。"
      case .model: return "本机简体中文语音模型未安装，或设备不支持。"
      case .microphone: return "请在系统设置 → 隐私与安全性 → 麦克风中允许 Rime 本地语音。"
      case .format: return "无法读取或转换麦克风音频。"
      case .device: return "所选麦克风不可用，请打开语音设置选择设备。"
      case .channel: return "无法读取所选麦克风，请在语音设置中尝试其他设备。"
      }
    }
  }

  func microphone() throws -> (AVAudioEngine, AVAudioInputNode, AVAudioFormat) {
    guard let device = VoiceDevices.selected(uid: deviceUID) else { throw VoiceError.device }
    let engine = AVAudioEngine(), input = engine.inputNode
    guard let unit = input.audioUnit else { throw VoiceError.device }
    var id = device.id
    var currentID: AudioDeviceID = 0
    var size = UInt32(MemoryLayout.size(ofValue: currentID))
    let read = AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &currentID, &size)
    if read != noErr || currentID != id {
      guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global,
                                 0, &id, UInt32(MemoryLayout.size(ofValue: id))) == noErr else { throw VoiceError.device }
    }
    let format = input.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else { throw VoiceError.format }
    guard inputChannel < format.channelCount else { throw VoiceError.channel }
    logger.info("Microphone format: \(format.sampleRate) Hz, \(format.channelCount) channels; selected channel: \(self.inputChannel)")
    return (engine, input, format)
  }
  nonisolated static func level(_ buffer: AVAudioPCMBuffer, channel: Int) -> Double {
    guard channel < buffer.format.channelCount, let data = buffer.floatChannelData else { return 0 }
    let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
    let pointer = buffer.format.isInterleaved ? data[0] + channel : data[channel]
    var sum: Double = 0
    for i in 0..<Int(buffer.frameLength) { let value = Double(pointer[i * stride]); sum += value * value }
    return sqrt(sum / Double(max(1, buffer.frameLength)))
  }
  func watchDevice(_ engine: AVAudioEngine) {
    let token = session
    let expected = audioConfiguration(engine)
    deviceObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
      Task { @MainActor in
        // Startup can enqueue a notification before the engine settles. A
        // notification alone does not mean the selected microphone changed.
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard let self, self.busy, self.session == token, self.engine === engine else { return }
        let selectedID = VoiceDevices.selected(uid: self.deviceUID)?.id
        if let expected, selectedID == expected.deviceID,
           expected.accepts(self.audioConfiguration(engine)) {
          if engine.isRunning { return }
          do { try engine.start(); return }
          catch { self.logger.error("Audio engine restart failed") }
        }
        await self.cancel(); self.emit("error", ["message": "输入设备发生变化，请检查设置并重新开始。"])
      }
    }
  }
  private func audioConfiguration(_ engine: AVAudioEngine) -> VoiceAudioConfiguration? {
    let input = engine.inputNode
    guard let unit = input.audioUnit else { return nil }
    var id: AudioDeviceID = 0
    var size = UInt32(MemoryLayout.size(ofValue: id))
    guard AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &id, &size) == noErr else { return nil }
    let format = input.outputFormat(forBus: 0)
    return VoiceAudioConfiguration(deviceID: id, sampleRate: format.sampleRate, channels: format.channelCount)
  }
  func startMeter() async throws {
    let token = session
    guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VoiceError.microphone }
    guard busy, session == token else { return }
    if let capture = try prepareBluetooth() {
      emit("connecting")
      capture.onBuffer = { [weak self] buffer in
        let level = Self.level(buffer, channel: 0)
        Task { @MainActor in
          guard let self, self.busy, self.session == token else { return }
          self.emit("audio", ["level": level])
        }
      }
      try await capture.start()
      guard busy, session == token else { await capture.stop(); return }
      emit("metering"); return
    }
    let (engine, input, format) = try microphone()
    let channel = inputChannel
    var frames = 0
    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
      frames += Int(buffer.frameLength)
      guard frames >= Int(format.sampleRate * 0.05) else { return }; frames = 0
      let level = Self.level(buffer, channel: channel)
      Task { @MainActor in
        guard let self, self.busy, self.session == token else { return }
        self.emit("audio", ["level": level])
      }
    }
    self.engine = engine
    try engine.start(); watchDevice(engine); emit("metering")
  }

  func prepareBluetooth() throws -> VoiceBluetoothCapture? {
    guard let device = VoiceDevices.selected(uid: deviceUID) else { throw VoiceError.device }
    guard device.bluetooth else { return nil }
    let token = session
    let capture = VoiceBluetoothCapture(device: device)
    capture.onError = { [weak self] message in
      Task { @MainActor in
        guard let self, self.busy, self.session == token else { return }
        await self.cancel(); self.emit("error", ["message": message])
      }
    }
    bluetoothCapture = capture
    return capture
  }

  @available(macOS 26.0, *)
  func transcriber() async throws -> SpeechTranscriber {
    guard SpeechTranscriber.isAvailable,
          let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-CN")),
          await SpeechTranscriber.installedLocales.contains(where: { $0.identifier == locale.identifier }) else {
      throw VoiceError.model
    }
    let newlyReserved = try await AssetInventory.reserve(locale: locale)
    releaseModel = { if newlyReserved { _ = await AssetInventory.release(reservedLocale: locale) } }
    return SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
  }

  @available(macOS 26.0, *)
  func observe(_ transcriber: SpeechTranscriber) -> Task<Void, Never> {
    let token = session
    return Task { [weak self] in
      do {
        for try await result in transcriber.results {
          guard let self, self.session == token else { break }
          self.emit("result", ["text": String(result.text.characters), "final": result.isFinal,
                               "start": result.range.start.seconds,
                               "end": CMTimeRangeGetEnd(result.range).seconds])
        }
      } catch {
        guard let self, self.session == token else { return }
        self.emit("error", ["message": error.localizedDescription])
      }
    }
  }

  func start() async throws {
    guard #available(macOS 26.0, *) else { throw VoiceError.system }
    let token = session
    let transcriber = try await transcriber()
    guard busy, token == session else { await releaseModel?(); releaseModel = nil; return }
    emit("permission")
    guard await AVCaptureDevice.requestAccess(for: .audio) else { throw VoiceError.microphone }
    guard busy, token == session else { return }
    let capture = try prepareBluetooth()
    let wired = capture == nil ? try microphone() : nil
    let natural = wired?.2 ?? VoiceBluetoothCapture.format
    guard natural.sampleRate > 0, natural.channelCount > 0,
          let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: natural),
          let converter = AudioConverter(from: natural, to: format, inputChannel: inputChannel) else { throw VoiceError.format }
    logger.info("Recognizer format: \(format.sampleRate) Hz, \(format.channelCount) channels")
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    try await analyzer.prepareToAnalyze(in: format)
    guard busy, token == session else { await analyzer.cancelAndFinishNow(); return }
    var continuation: AsyncStream<AnalyzerInput>.Continuation!
    let audio = AsyncStream<AnalyzerInput>(bufferingPolicy: .bufferingOldest(64)) { continuation = $0 }
    finishAudio = { continuation.finish() }
    resultTask = observe(transcriber)
    stopAnalysis = { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    cancelAnalysis = { await analyzer.cancelAndFinishNow() }
    var samplesSinceMeter = 0
    var samplesSinceLog = 0
    let channel = inputChannel
    let receive: (AVAudioPCMBuffer) -> Void = { [weak self] buffer in
      samplesSinceMeter += Int(buffer.frameLength)
      samplesSinceLog += Int(buffer.frameLength)
      let converted = converter.convert(buffer)
      if samplesSinceMeter >= Int(natural.sampleRate * 0.05) {
        samplesSinceMeter = 0
        let level = Self.level(buffer, channel: channel), frames = converted?.frameLength ?? 0
        let log = samplesSinceLog >= Int(natural.sampleRate * 2)
        if log { samplesSinceLog = 0 }
        Task { @MainActor in
          guard let self, self.session == token, self.busy else { return }
          if log { self.logger.info("Microphone RMS: \(level); converted frames: \(frames)") }
          self.emit("audio", ["level": level])
        }
      }
      if let converted,
         case .dropped = continuation.yield(AnalyzerInput(buffer: converted)) {
        Task { @MainActor [weak self] in
          guard let self, self.session == token else { return }
          await self.cancel()
          self.emit("error", ["message": "本机识别处理过慢，录音已停止。"])
        }
      }
    }
    self.engine = wired?.0
    try await analyzer.start(inputSequence: audio)
    guard busy, token == session else { return }
    if let capture {
      emit("connecting"); capture.onBuffer = receive; try await capture.start()
    } else if let (engine, input, _) = wired {
      input.installTap(onBus: 0, bufferSize: 2048, format: natural) { buffer, _ in receive(buffer) }
      try engine.start(); watchDevice(engine)
    }
    guard busy, token == session else { return }
    emit("listening")
  }

  func stop() async {
    guard busy else { return }
    feedTask?.cancel(); feedTask = nil
    let capture = bluetoothCapture; bluetoothCapture = nil; await capture?.stop()
    if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver); self.deviceObserver = nil }
    engine?.stop()
    engine?.inputNode.removeTap(onBus: 0)
    engine = nil
    finishAudio?()
    finishAudio = nil
    await stopAnalysis?()
    cloud = nil
    await resultTask?.value
    resultTask = nil
    stopAnalysis = nil
    cancelAnalysis = nil
    busy = false
    await releaseModel?(); releaseModel = nil
    emit("stopped")
  }

  func cancel() async {
    busy = false
    let capture = bluetoothCapture; bluetoothCapture = nil; await capture?.stop()
    feedTask?.cancel(); feedTask = nil
    if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver); self.deviceObserver = nil }
    engine?.stop()
    engine?.inputNode.removeTap(onBus: 0)
    engine = nil
    finishAudio?()
    finishAudio = nil
    await cancelAnalysis?()
    cloud?.cancel(); cloud = nil
    resultTask?.cancel()
    resultTask = nil
    stopAnalysis = nil
    cancelAnalysis = nil
    await releaseModel?(); releaseModel = nil
    emit("cancelled")
  }

  func startFixture(_ url: URL) async throws {
    guard #available(macOS 26, *) else { throw VoiceError.system }
    let token = session
    let transcriber = try await transcriber(), file = try AVAudioFile(forReading: url)
    guard busy, session == token,
          let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: file.processingFormat),
          let converter = AudioConverter(from: file.processingFormat, to: format) else { throw VoiceError.format }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    try await analyzer.prepareToAnalyze(in: format)
    let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingOldest(64))
    finishAudio = { continuation.finish() }
    stopAnalysis = { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    cancelAnalysis = { await analyzer.cancelAndFinishNow() }
    resultTask = observe(transcriber)
    try await analyzer.start(inputSequence: stream)
    emit("listening")
    feedTask = Task { [weak self] in
      do {
        while file.framePosition < file.length {
          guard !Task.isCancelled, let self, self.busy, self.session == token else { return }
          let capacity = AVAudioFrameCount(file.processingFormat.sampleRate * 0.1)
          guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity) else { break }
          try file.read(into: buffer)
          if let converted = converter.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
          self.emit("audio", ["level": Self.level(buffer, channel: 0)])
          try await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let self, self.busy, self.session == token else { return }
        self.feedTask = nil
        await self.stop()
      } catch {
        guard !Task.isCancelled, let self, self.session == token else { return }
        await self.cancel(); self.emit("error", ["message": error.localizedDescription])
      }
    }
  }

  func transcribeFile(_ url: URL) async throws {
    guard #available(macOS 26.0, *) else { throw VoiceError.system }
    let transcriber = try await transcriber()
    let file = try AVAudioFile(forReading: url)
    guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber], considering: file.processingFormat),
          let converter = AudioConverter(from: file.processingFormat, to: format) else { throw VoiceError.format }
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    let results = observe(transcriber)
    let audio = AsyncStream<AnalyzerInput> { continuation in
      while file.framePosition < file.length {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { break }
        do { try file.read(into: buffer) } catch { break }
        if let converted = converter.convert(buffer) { continuation.yield(AnalyzerInput(buffer: converted)) }
      }
      continuation.finish()
    }
    _ = try await analyzer.analyzeSequence(audio)
    try await analyzer.finalizeAndFinishThroughEndOfInput()
    await results.value
    await releaseModel?(); releaseModel = nil
    emit("stopped")
  }
}

final class AudioConverter: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let format: AVAudioFormat
  init?(from source: AVAudioFormat, to target: AVAudioFormat, inputChannel: Int = 0) {
    guard inputChannel >= 0, inputChannel < source.channelCount else { return nil }
    guard let converter = AVAudioConverter(from: source, to: target) else { return nil }
    self.converter = converter
    // Multi-channel USB interfaces may have no default channel layout.
    // Explicitly use the first physical input for mono speech recognition.
    if target.channelCount == 1 { converter.channelMap = [NSNumber(value: inputChannel)] }
    format = target
  }
  func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
    let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate)) + 32
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
    var supplied = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, state in
      if supplied { state.pointee = .noDataNow; return nil }
      supplied = true
      state.pointee = .haveData
      return buffer
    }
    return status != .error && error == nil && output.frameLength > 0 ? output : nil
  }
}

#if !VOICE_AUDIO_TEST
@main struct VoiceHelperMain {
  @MainActor static func main() {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let delegate = VoiceHelper()
    application.delegate = delegate
    application.run()
    withExtendedLifetime(delegate) {}
  }
}
#endif
