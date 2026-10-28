#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${root}/rime/.build/voice"
src="${root}/rime/native/voice"
mkdir -p "${out}/RimeVoiceBridge.swiftmodule" "${out}/RimeVoice.app/Contents/MacOS"
for arch in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -parse-as-library -O -target "${arch}-apple-macos13.0" \
    -module-cache-path "${root}/rime/.build/swift-module-cache" \
    "${src}/VoiceHelper.swift" "${src}/VoiceBluetoothCapture.swift" "${src}/VoiceDevices.swift" "${src}/VoiceTranscript.swift" \
    "${src}/DoubaoProtocol.swift" "${src}/DoubaoStream.swift" "${src}/VoiceHelperDoubao.swift" -lz -o "${out}/helper-${arch}"
  xcrun swiftc -swift-version 5 -parse-as-library -O -target "${arch}-apple-macos13.0" \
    -module-cache-path "${root}/rime/.build/swift-module-cache" \
    -emit-library -emit-module -module-name RimeVoiceBridge \
    -emit-module-path "${out}/RimeVoiceBridge.swiftmodule/${arch}-apple-macos.swiftmodule" \
    -Xlinker -install_name -Xlinker '@rpath/libRimeVoiceBridge.dylib' \
    "${src}/VoiceSetupGuide.swift" "${src}/VoiceRewrite.swift" "${src}/VoiceRewritePreferences.swift" "${src}/VoiceHistory.swift" "${src}/VoiceHistoryViews.swift" "${src}/VoiceEditing.swift" "${src}/VoiceController.swift" "${src}/VoiceViews.swift" "${src}/VoiceHUDPlacement.swift" "${src}/VoiceDevices.swift" \
    "${src}/VoiceClipboard.swift" "${src}/VoiceTextFormatter.swift" "${src}/VoiceDictionary.swift" "${src}/DoubaoDictionary.swift" "${src}/DoubaoDictionaryViews.swift" "${src}/DoubaoDictionaryPush.swift" "${src}/VoiceShortcuts.swift" "${src}/VoiceAccessibility.swift" "${src}/VoiceTranscript.swift" "${src}/VoiceCredentials.swift" "${src}/DoubaoProtocol.swift" "${src}/DoubaoPreferences.swift" \
    "${src}/SlashCommand.swift" "${src}/SlashSymbols.swift" "${src}/SlashSymbolData.swift" "${src}/SlashPaletteWindow.swift" "${src}/SlashPaletteController.swift" "${src}/GIFSearch.swift" "${src}/GIFSearchService.swift" "${src}/GIFClipboard.swift" "${src}/GIFPreferences.swift" \
    -lz -o "${out}/bridge-${arch}.dylib"
done
lipo -create "${out}/helper-arm64" "${out}/helper-x86_64" -output "${out}/RimeVoice.app/Contents/MacOS/RimeVoice"
lipo -create "${out}/bridge-arm64.dylib" "${out}/bridge-x86_64.dylib" -output "${out}/libRimeVoiceBridge.dylib"
cat > "${out}/RimeVoice.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>im.rime.inputmethod.Squirrel.Voice</string>
<key>CFBundleExecutable</key><string>RimeVoice</string>
<key>CFBundleName</key><string>Rime 语音</string>
<key>CFBundleDisplayName</key><string>Rime 语音</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>21</string>
<key>CFBundleShortVersionString</key><string>1.20</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSMicrophoneUsageDescription</key><string>采集语音转为文字；Apple 模式在本机识别，选择豆包模式时发送至火山引擎语音接口。</string>
</dict></plist>
PLIST
codesign --force --sign - "${out}/RimeVoice.app"
codesign --force --sign - "${out}/libRimeVoiceBridge.dylib"
