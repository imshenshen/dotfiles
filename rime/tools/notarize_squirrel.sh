#!/usr/bin/env bash
# Authentication stays in a user-created notarytool keychain profile, never source or argv.
set -euo pipefail
package="${1:?Usage: notarize_squirrel.sh package.pkg keychain-profile}"
profile="${2:?Missing notarytool keychain profile}"
[[ -f "${package}" && "${package}" == *.pkg ]] || exit 1
pkgutil --check-signature "${package}"
status_file="${package%.pkg}.notarization.json"
submission="$(python3 - "${status_file}" "${package}" <<'PY'
import hashlib,json,sys
from pathlib import Path
p=Path(sys.argv[1])
if p.exists():
 v=json.loads(p.read_text())
 if v.get('package_sha256')==hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest():print(v['id'])
PY
)"
if [[ -z "${submission}" ]]; then
    xcrun notarytool submit "${package}" --keychain-profile "${profile}" --output-format json > "${status_file}"
    submission="$(python3 - "${status_file}" "${package}" <<'PY'
import hashlib,json,sys
from pathlib import Path
p=Path(sys.argv[1]);v=json.loads(p.read_text());v['package_sha256']=hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
p.write_text(json.dumps(v,indent=2));print(v['id'])
PY
)"
fi
printf 'Notarization submission: %s\n' "${submission}"
started=${SECONDS}; last_status=''
while true; do
    response="$(xcrun notarytool info "${submission}" --keychain-profile "${profile}" --output-format json)"
    status="$(python3 -c 'import json,sys;print(json.load(sys.stdin)["status"])' <<< "${response}")"
    if [[ "${status}" != "${last_status}" ]]; then printf 'Notarization: %s\n' "${status}"; last_status="${status}"; fi
    case "${status}" in
        Accepted)
            xcrun stapler staple "${package}"
            xcrun stapler validate "${package}"
            spctl --assess --type install --verbose=2 "${package}"
            echo 'PASS: notarization accepted, ticket stapled and Gatekeeper validation passed'
            exit 0 ;;
        Invalid|Rejected)
            xcrun notarytool log "${submission}" --keychain-profile "${profile}" "${package%.pkg}.notarization-log.json"
            echo 'Notarization rejected; inspect the saved log before distribution' >&2
            exit 1 ;;
    esac
    if (( SECONDS - started >= ${SQUIRREL_NOTARY_MAX_SECONDS:-1200} )); then
        echo 'Still pending; run this command again to resume the same submission. Package is not ready for distribution.' >&2
        exit 75
    fi
    sleep 15
done
