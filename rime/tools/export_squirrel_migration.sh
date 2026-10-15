#!/usr/bin/env bash
# Export an existing build and a consistent personal Rime snapshot. No Keychain export.
set -euo pipefail
umask 077
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
package="${root}/rime/.build/squirrel/package/Squirrel.pkg"
source_app="${root}/rime/.build/squirrel/build/Build/Products/Release/Squirrel.app"
installed_app='/Library/Input Methods/Squirrel.app'
profile="${HOME}/Library/Rime"
export_dir="${1:-${root}/rime/.build/migration/Squirrel-$(date '+%Y%m%d-%H%M%S')}"
[[ -f "${package}" && -d "${profile}" ]] || { echo 'Existing package and Library/Rime are required' >&2; exit 1; }
[[ ! -e "${export_dir}" ]] || { echo 'Output directory already exists' >&2; exit 1; }
codesign --verify --deep --strict "${source_app}"
cmp "${source_app}/Contents/Resources/LocalBuild.plist" "${installed_app}/Contents/Resources/LocalBuild.plist"
mkdir -p "${export_dir}"
restart=false
cleanup() {
  rm -f "${export_dir}/.raw-voice-preferences.plist"
  if [[ "${restart}" == true ]]; then open "${installed_app}"; fi
}
trap cleanup EXIT
if pgrep -x Squirrel >/dev/null; then
  restart=true
  "${installed_app}/Contents/MacOS/Squirrel" --quit
  for attempt in 1 2 3 4 5; do
    if ! pgrep -x Squirrel >/dev/null; then break; fi
    sleep 1
  done
  if pgrep -x Squirrel >/dev/null; then echo 'Squirrel is still running; snapshot not created' >&2; exit 1; fi
fi
# Dereference dotfiles links; keep LevelDB write-ahead .log files. They are part
# of the learning databases, not diagnostic logs. Exclude generated dictionaries.
COPYFILE_DISABLE=1 tar -chzf "${export_dir}/Rime.tar.gz" \
  --exclude='./build' --exclude='./installation.yaml' --exclude='./sync' \
  --exclude='./squirrel.log' --exclude='./squirrel.log.*' --exclude='*.backup-*' \
  -C "${profile}" .
cp "${package}" "${export_dir}/Squirrel.pkg"
cp "${source_app}/Contents/Resources/LocalBuild.plist" "${export_dir}/LocalBuild.plist"
# Export only nonsecret, portable preferences. Device UID and developer fixture
# state are deliberately omitted; the destination starts with its own microphone.
if defaults export im.rime.inputmethod.Squirrel.Voice "${export_dir}/.raw-voice-preferences.plist" >/dev/null 2>&1; then
  plutil -convert xml1 "${export_dir}/.raw-voice-preferences.plist"
else
  plutil -create xml1 "${export_dir}/.raw-voice-preferences.plist"
fi
python3 - "${export_dir}" <<'PY'
import pathlib, plistlib, sys
folder = pathlib.Path(sys.argv[1])
source = plistlib.loads((folder / '.raw-voice-preferences.plist').read_bytes())
allowed = {'provider', 'doubaoResource', 'doubaoAuthMode', 'doubaoAppID', 'shortcut', 'mixedSpacing', 'pauseMilliseconds'}
with (folder / 'VoiceSettings.plist').open('wb') as f:
    plistlib.dump({k: v for k, v in source.items() if k in allowed}, f)
(folder / '.raw-voice-preferences.plist').unlink()
PY
cp "${root}/rime/migrate-mac.md" "${export_dir}/部署说明.md"
(cd "${export_dir}" && shasum -a 256 Squirrel.pkg Rime.tar.gz VoiceSettings.plist LocalBuild.plist > SHA256SUMS)
printf 'Migration folder: %s\n' "${export_dir}"
