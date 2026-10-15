import AVFoundation
import CoreMedia

@main struct BluetoothAudioTest {
  static func main() {
    let capture = VoiceBluetoothCapture(device: .init(id: 42, uid: "PUBLIC-TEST", name: "Public microphone", channels: 1))
    for (rate, channels, integer) in [(48000.0, 2, true), (16000.0, 1, false), (8000.0, 1, true), (24000.0, 1, true), (48000.0, 2, false)] {
      let format = AVAudioFormat(commonFormat: integer ? .pcmFormatInt16 : .pcmFormatFloat32,
        sampleRate: rate, channels: AVAudioChannelCount(channels), interleaved: integer)!
      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate / 10))!
      buffer.frameLength = buffer.frameCapacity
      if integer {
        for frame in 0..<Int(buffer.frameLength) { for channel in 0..<channels {
          buffer.int16ChannelData![0][frame * channels + channel] = channel == 0 ? 8192 : -16384
        } }
      } else {
        for channel in 0..<channels { for frame in 0..<Int(buffer.frameLength) {
          buffer.floatChannelData![channel][frame] = channel == 0 ? 0.25 : -0.5
        } }
      }
      var sample: CMSampleBuffer?
      var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(rate)), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
      precondition(CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
        makeDataReadyCallback: nil, refcon: nil, formatDescription: format.formatDescription,
        sampleCount: Int(buffer.frameLength), sampleTimingEntryCount: 1, sampleTimingArray: &timing,
        sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
      precondition(CMSampleBufferSetDataBufferFromAudioBufferList(sample!, blockBufferAllocator: kCFAllocatorDefault,
        blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: buffer.audioBufferList) == noErr)
      precondition(CMSampleBufferSetDataReady(sample!) == noErr)
      let restored = VoiceBluetoothCapture.pcmBuffer(sample!)!
      precondition(restored.frameLength == buffer.frameLength && restored.format.sampleRate == rate)
      let normalized = capture.normalize(restored)!
      precondition(normalized.format.sampleRate == 16000 && normalized.format.channelCount == 1)
      precondition(normalized.frameLength > 1000)
      let start = 100, end = Int(normalized.frameLength)
      let average = (start..<end).reduce(Float(0)) { $0 + normalized.floatChannelData![0][$1] } / Float(end-start)
      precondition(abs(average - 0.25) < 0.025, "Silent/wrong channel: \(rate) \(average)")
      print("PASS: captured \(integer ? "Int16" : "Float32") \(rate) Hz / \(channels) channels survives sample-buffer copy and format renegotiation; audible 16k mono")
    }
  }
}
