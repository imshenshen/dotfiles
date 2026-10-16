#!/usr/bin/env bash
# Build the upstream revision tested with this Rime configuration.
set -euo pipefail

dotfiles_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${dotfiles_root}/rime/.build/squirrel"
upstream_ref="${SQUIRREL_REF:-0cd71a6130a5866b0ae6ba0494929ebdc8211194}"

xcodebuild -version
command -v cmake >/dev/null
mkdir -p "$(dirname "${source_dir}")"
if [[ ! -d "${source_dir}/.git" ]]; then
    git clone --depth 1 https://github.com/rime/squirrel.git "${source_dir}"
fi
cd "${source_dir}"
[[ "$(git remote get-url origin)" == 'https://github.com/rime/squirrel.git' ]] || {
    echo 'Build directory is not the expected upstream checkout' >&2
    exit 1
}
ui_patch="${dotfiles_root}/rime/native/squirrel/cloud-badge.patch"
voice_patch="${dotfiles_root}/rime/native/squirrel/voice-input.patch"
updates_patch="${dotfiles_root}/rime/native/squirrel/pkg-only-updates.patch"
safety_patch="${dotfiles_root}/rime/native/squirrel/release-safety.patch"
# Remove only our known patch before checking for unrelated source changes.
if git apply --reverse --check "${safety_patch}" 2>/dev/null; then
    git apply --reverse "${safety_patch}"
fi
if git apply --reverse --check "${updates_patch}" 2>/dev/null; then
    git apply --reverse "${updates_patch}"
fi
if git apply --reverse --check "${voice_patch}" 2>/dev/null; then
    git apply --reverse "${voice_patch}"
fi
if git apply --reverse --check "${ui_patch}" 2>/dev/null; then
    git apply --reverse "${ui_patch}"
fi
git diff --quiet
git diff --cached --quiet
git fetch --depth 1 origin "${upstream_ref}"
git checkout --detach FETCH_HEAD
# The binary dependency shortcut only needs these two source submodules.
git submodule update --init --depth 1 librime plum
grep -q '_refresh_ui' sources/ReservedProperty.swift
git apply --check "${ui_patch}"
git apply "${ui_patch}"
git apply --check "${voice_patch}"
git apply "${voice_patch}"
git apply --check "${updates_patch}"
git apply "${updates_patch}"
git apply --check "${safety_patch}"
git apply "${safety_patch}"
SQUIRREL_BUNDLED_RECIPES=':preset' bash ./action-install.sh
bash "${dotfiles_root}/rime/tools/build_voice.sh"
xcodebuild -project Squirrel.xcodeproj -configuration Release -scheme Squirrel \
    -derivedDataPath build ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    SWIFT_INCLUDE_PATHS="${dotfiles_root}/rime/.build/voice" \
    OTHER_LDFLAGS="\$(inherited) -L${dotfiles_root}/rime/.build/voice -lRimeVoiceBridge" \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES build

app_dir="${source_dir}/build/Build/Products/Release/Squirrel.app"
# TCC attributes a directly spawned recorder to its responsible input method.
plutil -replace NSMicrophoneUsageDescription -string '采集语音转为文字；Apple 模式在本机识别，选择豆包模式时发送至火山引擎语音接口。' "${app_dir}/Contents/Info.plist"
ditto "${dotfiles_root}/rime/.build/voice/RimeVoice.app" "${app_dir}/Contents/Helpers/RimeVoice.app"
ditto "${dotfiles_root}/rime/.build/voice/libRimeVoiceBridge.dylib" "${app_dir}/Contents/Frameworks/libRimeVoiceBridge.dylib"
# Include all recipe data without relying on upstream's generated Xcode resource list.
ditto "${source_dir}/data/plum" "${app_dir}/Contents/SharedSupport"
ditto "${source_dir}/data/opencc" "${app_dir}/Contents/SharedSupport/opencc"
ditto "${source_dir}/lib/rime-plugins" "${app_dir}/Contents/Frameworks/rime-plugins"
bash "${dotfiles_root}/rime/tools/build_cloud_plugin.sh"
ditto "${dotfiles_root}/rime/.build/cloud-pinyin/librime-cloud-pinyin.dylib" \
    "${app_dir}/Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib"
ditto "${dotfiles_root}/rime/.build/boost-1.89.0/LICENSE_1_0.txt" \
    "${app_dir}/Contents/Resources/CloudPinyinBoostLicense.txt"
# Prebuild before the final signature; installer must not change signed resources.
(cd "${app_dir}/Contents/SharedSupport" && ../MacOS/Squirrel --build)
record="${app_dir}/Contents/Resources/LocalBuild.plist"
# Record the commit because upstream still labels this build as version 1.1.2.
rm -f "${record}"
plutil -create xml1 "${record}"
plutil -insert UpstreamRepository -string 'https://github.com/rime/squirrel' "${record}"
plutil -insert UpstreamCommit -string "$(git rev-parse HEAD)" "${record}"
plutil -insert BuiltAtUTC -string "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "${record}"
plutil -insert Architectures -string 'arm64 x86_64' "${record}"
plutil -insert LibrimeVersion -string "$(sed -n 's/^rime_version=//p' action-install.sh)" "${record}"
plutil -insert CloudPinyinVersion -string '3' "${record}"
plutil -insert WubiMixedFifthCode -bool true "${record}"
plutil -insert CloudBadgeUI -bool true "${record}"
plutil -insert VoiceInputVersion -string '15' "${record}"
plutil -insert SharedUserDictionary -bool true "${record}"
plutil -insert MixedTextSpacing -bool true "${record}"
plutil -insert DirectTextSpacingVersion -string '1' "${record}"
plutil -insert SideSpecificModifierShortcut -bool true "${record}"
plutil -insert GlobalDictation -bool true "${record}"
plutil -insert NativeCompositionConfirmation -bool true "${record}"
plutil -insert AccessibilityOnlyShortcut -bool true "${record}"
plutil -insert ActiveScreenVoiceHUD -bool true "${record}"
plutil -insert SilentVoiceEscape -bool true "${record}"
plutil -insert RelativeMarkedSelection -bool true "${record}"
plutil -insert NoForcedLogout -bool true "${record}"
plutil -insert FreshVoiceHUD -bool true "${record}"
plutil -insert VoiceUndoEnabled -bool false "${record}"
plutil -insert PkgOnlyUpdates -bool true "${record}"
plutil -insert MicrophonePermissionDescription -bool true "${record}"
plutil -insert SeparateStatusIcon -bool false "${record}"
plutil -insert BluetoothCapture -bool true "${record}"
plutil -insert CredentialPaste -bool true "${record}"
plutil -insert DoubaoSpeechTwoPass -bool true "${record}"
plutil -insert LocalSpeechEngine -string 'Apple SpeechAnalyzer' "${record}"
codesign --force --deep --sign - --preserve-metadata=identifier,entitlements,flags "${app_dir}"
codesign --verify --deep --strict "${app_dir}"
# Package directly: `make package` would rebuild after adding the provenance file.
bash "${dotfiles_root}/rime/tools/package_squirrel.sh"
printf 'Built app: %s\nInstaller: %s\n' "${app_dir}" "${source_dir}/package/Squirrel.pkg"
