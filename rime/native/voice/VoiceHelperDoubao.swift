import Foundation
import AVFoundation

extension VoiceHelper {
  nonisolated static func pcm16(_ buffer: AVAudioPCMBuffer) -> Data {
    guard let pointer = buffer.floatChannelData?[0] else { return Data() }
    var samples = [Int16](repeating: 0, count: Int(buffer.frameLength))
    for index in samples.indices {
      let value = pointer[index].isFinite ? pointer[index] : 0
      samples[index] = Int16(max(-32768, min(32767, Double(value) * 32768))).littleEndian
    }
    return samples.withUnsafeBytes { Data($0) }
  }
  func startCloud(_ command: [String: String]) async throws {
    let config = DoubaoConfiguration(apiKey: command["apiKey"] ?? "", appID: command["appID"] ?? "",
      accessToken: command["accessToken"] ?? "", resource: command["resource"] ?? "volc.seedasr.sauc.duration",
      pauseMilliseconds: Int(command["pauseMilliseconds"] ?? "") ?? 1600,
      hotwords: (try? JSONDecoder().decode([String].self, from: Data((command["hotwords"] ?? "[]").utf8))) ?? [],
      removeDisfluencies: command["removeDisfluencies"] == "true")
    _ = try config.request()
    let stream = DoubaoStream(), token = session
    stream.onResult = { [weak self] result in
      guard let self, self.busy, self.session == token else { return }
      self.emit("result", ["text": result.text, "final": result.final, "start": result.start, "end": result.end])
    }
    stream.onError = { [weak self] error in
      Task { @MainActor in
        guard let self, self.busy, self.session == token else { return }
        await self.cancel(); self.emit("error", ["message": error.localizedDescription])
      }
    }
    cloud = stream
    try await stream.start(config)
    stopAnalysis = { await stream.finish() }; cancelAnalysis = { stream.cancel() }
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
    if command["fixture"] == "/tmp/rime-voice-acceptance/speech.aiff" {
      let file = try AVAudioFile(forReading: URL(fileURLWithPath: command["fixture"]!))
      guard let converter = AudioConverter(from: file.processingFormat, to: format, inputChannel: 0) else { throw VoiceError.format }
      emit("listening")
      feedTask = Task { [weak self] in
        do {
          let capacity = AVAudioFrameCount(file.processingFormat.sampleRate * 0.1)
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: capacity)!
          while !Task.isCancelled, file.framePosition < file.length {
            try file.read(into: buffer, frameCount: capacity)
            if let converted = converter.convert(buffer) { stream.submit(Self.pcm16(converted)) }
            self?.emit("audio", ["level": Self.level(buffer, channel: 0)])
            try await Task.sleep(nanoseconds: 100_000_000)
          }
          guard !Task.isCancelled, let self else { return }; self.feedTask = nil; await self.stop()
        } catch {
          guard !Task.isCancelled, let self else { return }; await self.cancel(); self.emit("error", ["message": "测试音频读取失败。"])
        }
      }
      return
    }
    guard await AVCaptureDevice.requestAccess(for: .audio), busy, session == token else { throw VoiceError.microphone }
    let capture = try prepareBluetooth()
    let wired = capture == nil ? try microphone() : nil
    let natural = wired?.2 ?? VoiceBluetoothCapture.format
    guard let converter = AudioConverter(from: natural, to: format, inputChannel: inputChannel) else { throw VoiceError.format }
    let channel = inputChannel
    let receive: (AVAudioPCMBuffer) -> Void = { [weak self] buffer in
      let level = Self.level(buffer, channel: channel)
      let data = converter.convert(buffer).map(Self.pcm16)
      DispatchQueue.main.async {
        guard let self, self.busy, self.session == token else { return }
        if let data { stream.submit(data) }; self.emit("audio", ["level": level])
      }
    }
    self.engine = wired?.0
    if let capture {
      emit("connecting"); capture.onBuffer = receive; try await capture.start()
    } else if let (engine, input, _) = wired {
      input.installTap(onBus: 0, bufferSize: 2048, format: natural) { buffer, _ in receive(buffer) }
      try engine.start(); watchDevice(engine)
    }
    guard busy, session == token else { return }
    emit("listening")
  }
}
