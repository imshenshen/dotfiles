#!/usr/bin/env bash
# Single install/upgrade package. All defaults live inside the application.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${root}/rime/.build/squirrel"
source_app="${source_dir}/build/Build/Products/Release/Squirrel.app"
package_dir="${source_dir}/package"
config="${SQUIRREL_SIGN_CONFIG:-${root}/rime/.build/signing/release.json}"
read_signing() {
    python3 - "${config}" "$1" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1]); values = json.loads(p.read_text()) if p.exists() else {}
value = values.get(sys.argv[2], '')
assert isinstance(value, str) and '\n' not in value and '\r' not in value
print(value)
PY
}
identity="${SQUIRREL_SIGN_IDENTITY:-$(read_signing application_identity)}"
team="${SQUIRREL_SIGN_TEAM:-$(read_signing team)}"
installer_identity="${SQUIRREL_INSTALLER_IDENTITY:-$(read_signing installer_identity)}"
notary_profile="${SQUIRREL_NOTARY_PROFILE:-$(read_signing notary_profile)}"
if [[ "${SQUIRREL_ADHOC:-0}" == 1 ]]; then
    identity=''; team=''; installer_identity=''; notary_profile=''
fi
if [[ -n "${identity}${team}${installer_identity}${notary_profile}" ]]; then
    [[ -n "${identity}" && -n "${team}" && -n "${installer_identity}" ]] || {
        echo 'Release signing requires Application identity, Team ID and Installer identity' >&2; exit 1;
    }
fi
if [[ -n "${identity}" && -z "${notary_profile}" ]]; then
    echo 'Formal releases require notarization. First run: bash rime/tools/configure_notarization.sh' >&2
    exit 1
fi
stage="$(mktemp -d "${root}/rime/.build/release-stage.XXXXXX")"
trap 'rm -rf "${stage}"' EXIT
mkdir -p "${stage}/root" "${stage}/packages"
ditto "${source_app}" "${stage}/root/Squirrel.app"
app="${stage}/root/Squirrel.app"
# The responsible input-method process requests permission before launching its helper.
# Keep this invariant even when packaging an app built directly by xcodebuild.
plutil -replace NSMicrophoneUsageDescription -string '采集语音转为文字；Apple 模式在本机识别，选择豆包模式时发送至火山引擎语音接口。' "${app}/Contents/Info.plist"
[[ -n "$(plutil -extract NSMicrophoneUsageDescription raw "${app}/Contents/Helpers/RimeVoice.app/Contents/Info.plist")" ]]
bash "${root}/rime/tools/prepare_release_data.sh" "${app}"
version="${SQUIRREL_RELEASE_VERSION:-$(date -u '+%Y%m%d.%H%M%S')}"
plutil -replace CFBundleVersion -string "${version}" "${app}/Contents/Info.plist"
# Upstream Sparkle packages cannot preserve the custom voice/cloud implementation.
/usr/libexec/PlistBuddy -c 'Delete :SUFeedURL' "${app}/Contents/Info.plist" 2>/dev/null || true
plutil -replace SUEnableAutomaticChecks -bool false "${app}/Contents/Info.plist"
plutil -replace ReleaseVersion -string "${version}" "${app}/Contents/Resources/LocalBuild.plist"
if [[ -n "${identity}" ]]; then
    python3 "${root}/rime/tools/sign_squirrel_app.py" "${app}" --identity "${identity}" --team "${team}"
else
    codesign --force --deep --sign - --preserve-metadata=identifier,entitlements,flags "${app}"
fi
codesign --verify --deep --strict "${app}"
pkgbuild --root "${stage}/root" --filter '.*\.swiftmodule$' \
    --component-plist "${package_dir}/Squirrel-component.plist" \
    --identifier im.rime.inputmethod.Squirrel --version "${version}" \
    --install-location '/Library/Input Methods' --scripts "${root}/rime/distribution/scripts" \
    "${stage}/packages/Squirrel-component.pkg"
sed "s/@VERSION@/${version}/" "${package_dir}/Distribution" > "${stage}/Distribution.xml"
mkdir -p "${root}/rime/dist"
output="${root}/rime/dist/Squirrel-${version}.pkg"
sign_options=()
if [[ -n "${installer_identity}" ]]; then sign_options=(--sign "${installer_identity}" --timestamp); fi
productbuild "${sign_options[@]}" --distribution "${stage}/Distribution.xml" \
    --package-path "${stage}/packages" --resources "${package_dir}" "${output}"
if [[ -n "${installer_identity}" ]]; then pkgutil --check-signature "${output}"; fi
if [[ -n "${notary_profile}" ]]; then
    bash "${root}/rime/tools/notarize_squirrel.sh" "${output}" "${notary_profile}"
fi
# Preserve the existing install/rollback tool's expected source and package paths.
# This is the verified staged app, including release defaults and its final signature.
rm -rf "${source_app}"
ditto "${app}" "${source_app}"
cp "${output}" "${package_dir}/Squirrel.pkg"
printf 'Release package: %s\n' "${output}"
