#!/usr/bin/env bash
# Stage only distributable defaults. Never package ~/Library/Rime or preferences.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app="${1:?Usage: prepare_release_data.sh path/to/staged/Squirrel.app}"
shared="${app}/Contents/SharedSupport"
ditto "${root}/rime/distribution/data" "${shared}"
for file in default.custom.yaml squirrel.custom.yaml wubi86.custom.yaml rime_frost.custom.yaml luna_pinyin_simp.custom.yaml wubi86_pinyin.schema.yaml; do
    ditto "${root}/rime/${file}" "${shared}/${file}"
done
ditto "${root}/rime/lua/wubi_pinyin_router.lua" "${shared}/lua/wubi_pinyin_router.lua"
ditto "${root}/rime/lua/slash_literal.lua" "${shared}/lua/slash_literal.lua"
ditto "${root}/rime/distribution/VoiceDefaults.plist" "${app}/Contents/Resources/VoiceDefaults.plist"
ditto "${root}/rime/distribution/licenses" "${app}/Contents/Resources/DefaultDataLicenses"
ditto "${root}/rime/distribution/README.md" "${app}/Contents/Resources/DefaultDataSources.md"
# The stabledb editor creates this file in the user's own directory on first save.
printf '# Personal phrases belong in ~/Library/Rime/custom_phrase.txt\n' > "${shared}/custom_phrase.txt"
rm -rf "${shared}/build"
(cd "${shared}" && ../MacOS/rime_deployer --build . . ./build)
[[ -f "${shared}/build/wubi86.schema.yaml" && -f "${shared}/build/rime_frost.table.bin" ]]
# librime's deployer writes a build-machine identity even in a clean directory.
# It is runtime state, not a distributable default.
rm -f "${shared}/installation.yaml" "${shared}/user.yaml"
python3 - "${shared}" "${app}/Contents/Resources/VoiceDefaults.plist" <<'PY'
from pathlib import Path
import plistlib, sys
shared = Path(sys.argv[1])
for p in shared.rglob('*'):
    if p.is_symlink() or p.name.endswith('.userdb') or p.name in ('mixed_user_dictionary.json', 'installation.yaml', 'user.yaml'):
        raise SystemExit(f'Non-distributable state in release: {p}')
allowed = {'provider', 'doubaoResource', 'doubaoAuthMode', 'shortcut', 'mixedSpacing', 'pauseMilliseconds', 'removeDisfluencies'}
if not plistlib.load(open(sys.argv[2], 'rb')).keys() <= allowed:
    raise SystemExit('Private or unsupported preference in VoiceDefaults.plist')
PY
