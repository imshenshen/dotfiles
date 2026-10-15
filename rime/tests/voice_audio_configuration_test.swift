import Foundation
@main struct AudioConfigurationTest {
  static func main() {
    let microphone = VoiceAudioConfiguration(deviceID: 42, sampleRate: 48000, channels: 1)
    precondition(microphone.accepts(microphone)) // Startup/output-device notifications are harmless.
    precondition(!microphone.accepts(nil)) // Disconnected/unreadable device.
    precondition(!microphone.accepts(.init(deviceID: 43, sampleRate: 48000, channels: 1)))
    precondition(!microphone.accepts(.init(deviceID: 42, sampleRate: 44100, channels: 1)))
    precondition(!microphone.accepts(.init(deviceID: 42, sampleRate: 48000, channels: 2)))
    precondition(!microphone.accepts(.init(deviceID: 42, sampleRate: 0, channels: 0)))
    let invalid = VoiceAudioConfiguration(deviceID: 0, sampleRate: .nan, channels: 0)
    precondition(!invalid.accepts(invalid))
    print("PASS: unchanged microphone configuration survives notifications; changed, disconnected and invalid formats are rejected")
  }
}
