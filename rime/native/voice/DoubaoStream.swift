import Foundation
import OSLog

@MainActor final class DoubaoStream {
  var onResult: ((DoubaoRecognition) -> Void)?
  var onError: ((Error) -> Void)?
  private var session: URLSession?
  private var socket: URLSessionWebSocketTask?
  private var receiver: Task<Void, Never>?
  private var sender: Task<Void, Never>?
  private var continuation: AsyncStream<Data>.Continuation?
  private var pending = Data()
  private var tracker = DoubaoResultTracker()
  private var accepting = false
  private var finished = false
  private var failed = false
  private var submittedBytes = 0
  private var sentBytes = 0
  private var sentPackets = 0
  private let diagnosticID = UUID().uuidString
  private var startedAt = ProcessInfo.processInfo.systemUptime
  private let packetSize = 6400 // 200 ms of 16 kHz mono PCM16.
  private let logger = Logger(subsystem: "im.rime.inputmethod.Squirrel", category: "Doubao")
  private func transportError(_ socket: URLSessionWebSocketTask) -> DoubaoError {
    if let status = (socket.response as? HTTPURLResponse)?.statusCode, status != 101 { return .handshake(status) }
    return .transport
  }

  func start(_ config: DoubaoConfiguration, endpoint: URL = DoubaoConfiguration.endpoint) async throws {
    startedAt = ProcessInfo.processInfo.systemUptime
    logger.info("ASR start: id=\(self.diagnosticID, privacy: .public), ddc=\(config.removeDisfluencies)")
    let initial = try DoubaoProtocol.initial(pauseMilliseconds: config.pauseMilliseconds, hotwords: config.hotwords, removeDisfluencies: config.removeDisfluencies)
    let options = URLSessionConfiguration.ephemeral
    options.timeoutIntervalForRequest = 15; options.timeoutIntervalForResource = 3600
    options.httpCookieStorage = nil; options.urlCredentialStorage = nil
    let session = URLSession(configuration: options), socket = session.webSocketTask(with: try config.request(url: endpoint))
    socket.maximumMessageSize = DoubaoProtocol.maximumPayload + 64
    self.session = session; self.socket = socket; socket.resume()
    do { try await socket.send(.data(initial)) }
    catch { let failure = transportError(socket); logger.error("Cloud connection: \(failure.localizedDescription, privacy: .public)"); cancel(); throw failure }
    accepting = true
    let queue = AsyncStream<Data>(bufferingPolicy: .bufferingOldest(100)) { continuation = $0 }
    sender = Task { [weak self] in
      do {
        for await data in queue {
          try Task.checkCancellation()
          try await socket.send(.data(DoubaoProtocol.audio(data)))
          guard let self else { return }
          self.sentBytes += data.count; self.sentPackets += 1
          if self.sentPackets == 1 { self.logAudioMetadata("first-packet") }
        }
      }
      catch { if !Task.isCancelled, let self { self.fail(self.transportError(socket)) } }
    }
    receiver = Task { [weak self] in
      do {
        while !Task.isCancelled {
          let message = try await socket.receive()
          guard let self else { return }
          guard case .data(let data) = message else {
            self.logger.error("Unexpected WebSocket message kind: text"); throw DoubaoError.malformed
          }
          let response: DoubaoResponse
          do { response = try DoubaoProtocol.unpack(data) }
          catch {
            if data.count >= 4 {
              let header = [UInt8](data.prefix(4))
              self.logger.error("Rejected server frame metadata: version=\(header[0] >> 4), words=\(header[0] & 15), type=\(header[1] >> 4), flags=\(header[1] & 15), serialization=\(header[2] >> 4), compression=\(header[2] & 15), bytes=\(data.count)")
            }
            throw error
          }
          for item in self.tracker.changes(response) { self.onResult?(item) }
          if response.last { self.finished = true; return }
        }
      } catch {
        guard !Task.isCancelled, let self else { return }; self.fail(error is DoubaoError ? error : self.transportError(socket))
      }
    }
  }
  func submit(_ data: Data) {
    guard accepting, !failed else { return }
    submittedBytes += data.count
    pending.append(data)
    while pending.count >= packetSize {
      let packet = Data(pending.prefix(packetSize)); pending.removeFirst(packetSize)
      if case .dropped = continuation?.yield(packet) { fail(DoubaoError.overflow); return }
    }
  }
  func finish() async {
    guard accepting else { return }; accepting = false
    logAudioMetadata("finish-requested")
    // A quick stop before capture delivers PCM is a silent cancellation, not
    // an empty recognition request for the server to reject with 45000002.
    guard submittedBytes > 0 else { cancel(); return }
    if !pending.isEmpty {
      if case .dropped = continuation?.yield(pending) { pending.removeAll(); fail(DoubaoError.overflow); return }
      pending.removeAll()
    }
    continuation?.finish(); continuation = nil
    await sender?.value
    guard !failed, let socket else { return }
    logAudioMetadata("final-marker")
    do { try await socket.send(.data(DoubaoProtocol.audio(Data(), last: true))) }
    catch { fail(DoubaoError.transport); return }
    for _ in 0..<100 {
      if finished || failed { break }
      try? await Task.sleep(nanoseconds: 100_000_000)
      if Task.isCancelled { cancel(); return }
    }
    if !finished && !failed { fail(DoubaoError.timeout) }
    cancel()
  }
  private func fail(_ error: Error) {
    guard !failed else { return }; failed = true; accepting = false
    logAudioMetadata("failure")
    if let safe = error as? DoubaoError { logger.error("Cloud recognition: \(safe.localizedDescription, privacy: .public)") }
    continuation?.finish(); continuation = nil
    socket?.cancel(with: .goingAway, reason: nil)
    onError?(error)
  }
  private func logAudioMetadata(_ phase: String) {
    let elapsedMilliseconds = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
    logger.info("ASR audio: id=\(self.diagnosticID, privacy: .public), phase=\(phase, privacy: .public), elapsedMs=\(elapsedMilliseconds), submittedBytes=\(self.submittedBytes), sentBytes=\(self.sentBytes), sentPackets=\(self.sentPackets), pendingBytes=\(self.pending.count)")
  }
  func cancel() {
    accepting = false; continuation?.finish(); continuation = nil
    sender?.cancel(); receiver?.cancel(); sender = nil; receiver = nil
    socket?.cancel(with: .normalClosure, reason: nil); socket = nil
    session?.invalidateAndCancel(); session = nil; pending.removeAll()
  }
}
