#!/usr/bin/env bash
# Install the package produced by build_squirrel.sh, keeping a local rollback copy.
set -euo pipefail

dotfiles_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="${dotfiles_root}/rime/.build/squirrel"
package_path="${source_dir}/package/Squirrel.pkg"
source_app="${source_dir}/build/Build/Products/Release/Squirrel.app"
installed_app='/Library/Input Methods/Squirrel.app'
[[ -f "${package_path}" && -f "${source_app}/Contents/Resources/LocalBuild.plist" ]] || {
    echo 'Run build_squirrel.sh before installing' >&2
    exit 1
}
codesign --verify --deep --strict "${source_app}"
backup_root="${dotfiles_root}/rime/.build/backups"
mkdir -p "${backup_root}"
backup_dir="$(mktemp -d "${backup_root}/$(date '+%Y%m%d-%H%M%S').XXXXXX")"
if [[ -d "${installed_app}" ]]; then
    ditto "${installed_app}" "${backup_dir}/Squirrel.app"
    "${installed_app}/Contents/MacOS/Squirrel" --quit
fi
# Let graceful shutdown finish before copying user dictionaries.
for attempt in 1 2 3 4 5; do
    if ! pgrep -x Squirrel >/dev/null; then break; fi
    sleep 1
done
if pgrep -x Squirrel >/dev/null; then
    echo 'Squirrel is still running; close it before backing up user data' >&2
    exit 1
fi
if [[ -d "${HOME}/Library/Rime" ]]; then
    ditto "${HOME}/Library/Rime" "${backup_dir}/Rime"
    # Freeze linked dotfiles too: preserving a symlink alone is not a config backup.
    while IFS= read -r -d '' linked_file; do
        if [[ -f "${linked_file}" ]]; then
            ditto "${linked_file}" "${linked_file}.snapshot"
            mv "${linked_file}.snapshot" "${linked_file}"
        fi
    done < <(find "${backup_dir}/Rime" -type l -print0)
fi
printf '%s\n' "${backup_dir}" > "${backup_root}/latest.txt"
if [[ ! -f "${backup_root}/original.txt" ]]; then
    printf '%s\n' "${backup_dir}" > "${backup_root}/original.txt"
fi
printf 'Backup: %s\n' "${backup_dir}"
# macOS handles the password in its own authentication dialog.
# If cancelled, reopen the previous app before exiting.
if ! osascript - "${package_path}" <<'APPLESCRIPT'
on run argv
    set packagePath to item 1 of argv
    do shell script "/usr/sbin/installer -pkg " & quoted form of packagePath & " -target /" with administrator privileges
end run
APPLESCRIPT
then
    if [[ -d "${installed_app}" ]]; then open "${installed_app}"; fi
    exit 1
fi
codesign --verify --deep --strict "${installed_app}"
cmp "${source_app}/Contents/MacOS/Squirrel" "${installed_app}/Contents/MacOS/Squirrel"
for voice_file in Contents/Frameworks/libRimeVoiceBridge.dylib Contents/Helpers/RimeVoice.app/Contents/MacOS/RimeVoice; do
    cmp "${source_app}/${voice_file}" "${installed_app}/${voice_file}"
done
if [[ -f "${source_app}/Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib" ]]; then
    cmp "${source_app}/Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib" \
        "${installed_app}/Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib"
fi
printf 'Installed source commit: '
plutil -extract UpstreamCommit raw "${installed_app}/Contents/Resources/LocalBuild.plist"
printf 'Package files verified. Input-source menu and actual typing still require desktop acceptance.\n'
