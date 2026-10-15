#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${root}/rime/.build/voice"
[[ -x "${out}/RimeVoice.app/Contents/MacOS/RimeVoice" ]] || bash "${root}/rime/tools/build_voice.sh"
xcrun swiftc -swift-version 5 -parse-as-library -DVOICE_AUDIO_TEST \
  -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${root}/rime/native/voice/VoiceHelper.swift" "${root}/rime/native/voice/VoiceBluetoothCapture.swift" "${root}/rime/native/voice/VoiceDevices.swift" "${root}/rime/native/voice/VoiceTranscript.swift" \
  "${root}/rime/native/voice/DoubaoProtocol.swift" "${root}/rime/native/voice/DoubaoStream.swift" \
  "${root}/rime/native/voice/VoiceHelperDoubao.swift" -lz "${root}/rime/tests/voice_audio_test.swift" \
  -o "${out}/voice-audio-test"
"${out}/voice-audio-test"
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${root}/rime/native/voice/VoiceEditing.swift" "${root}/rime/tests/voice_editing_test.swift" \
  -o "${out}/voice-editing-test"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/rime-voice-test.XXXXXX")"
trap 'rm -rf "${fixture}"' EXIT
say -v Tingting -o "${fixture}/speech.aiff" '你好，这是本地语音输入测试。今天我们测试实时上屏，手动编辑和撤回。'
"${out}/RimeVoice.app/Contents/MacOS/RimeVoice" --transcribe "${fixture}/speech.aiff" > "${fixture}/results.jsonl"
"${out}/voice-editing-test" "${fixture}/results.jsonl"
xcrun swiftc -parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${root}/rime/native/voice/VoiceTranscript.swift" "${root}/rime/tests/voice_transcript_test.swift" \
  -o "${out}/voice-transcript-test"
"${out}/voice-transcript-test"
xcrun swiftc -parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${root}/rime/native/voice/VoiceEditing.swift" "${root}/rime/native/voice/VoiceTranscript.swift" \
  "${root}/rime/tests/voice_manual_resume_test.swift" -o "${out}/voice-manual-resume-test"
"${out}/voice-manual-resume-test"
