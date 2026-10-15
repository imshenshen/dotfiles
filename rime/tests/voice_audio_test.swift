import AVFoundation

@main struct AudioTest {
  static func main() {
    for channels: AVAudioChannelCount in [1, 2, 18, 20] {
      let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)!
      let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000,
                                 interleaved: false, channelLayout: layout)
      let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
      let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 4800)!
      input.frameLength = 4800
      for channel in 0..<Int(channels) {
        for sample in 0..<4800 { input.floatChannelData![channel][sample] = channel == 0 ? 0.4 : -0.4 }
      }
      let converter = AudioConverter(from: source, to: target)!
      let result = converter.convert(input)!
      assert(result.frameLength > 1000)
      let data = result.floatChannelData![0]
      let average = (100..<Int(result.frameLength)).reduce(Float(0)) { $0 + data[$1] } / Float(result.frameLength - 100)
      assert(abs(average - 0.4) < 0.01, "Wrong channel or silent output: \(channels), \(average)")
      print("PASS: \(channels)-channel 48 kHz input to first-channel 16 kHz speech; \(result.frameLength) frames")
      if channels > 1 {
        let other = AudioConverter(from: source, to: target, inputChannel: 1)!.convert(input)!
        let data = other.floatChannelData![0]
        let average = (100..<Int(other.frameLength)).reduce(Float(0)) { $0 + data[$1] } / Float(other.frameLength - 100)
        assert(abs(average + 0.4) < 0.01)
        assert(AudioConverter(from: source, to: target, inputChannel: Int(channels)) == nil)
        print("PASS: selecting second channel and rejecting nonexistent channel")
      }
    }
    assert(VoiceDevices.selected(uid: "rime-nonexistent-test-device") == nil)
    for device in VoiceDevices.inputs() { assert(!device.uid.isEmpty && device.channels > 0) }
    print("PASS: device inventory and disconnected-device rejection")
  }
}
