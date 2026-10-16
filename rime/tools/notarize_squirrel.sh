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
 try: v=json.loads(p.read_text())
 except (ValueError,OSError): v={}
 digest=hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
 if digest in (v.get('package_sha256'),v.get('stapled_package_sha256')) and isinstance(v.get('id'),str):print(v['id'])
PY
)"
if [[ -z "${submission}" ]]; then
    temporary="$(mktemp "${status_file}.submission.XXXXXX")"
    trap 'rm -f "${temporary}"' EXIT
    xcrun notarytool submit "${package}" --keychain-profile "${profile}" --output-format json > "${temporary}"
    submission="$(python3 - "${temporary}" "${package}" <<'PY'
import hashlib,json,sys
from pathlib import Path
p=Path(sys.argv[1]);v=json.loads(p.read_text())
if not isinstance(v.get('id'),str) or not v['id']:raise SystemExit('Submission response has no ID')
v['package_sha256']=hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest()
p.write_text(json.dumps(v,indent=2));print(v['id'])
PY
)"
    mv "${temporary}" "${status_file}"
    trap - EXIT
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
            # Stapling changes the hash; remember it before later validation so
            # a retry reuses this accepted submission rather than uploading again.
            python3 - "${status_file}" "${package}" <<'PY'
import hashlib,json,os,sys,tempfile
from pathlib import Path
p=Path(sys.argv[1]);v=json.loads(p.read_text())
v['stapled_package_sha256']=hashlib.sha256(Path(sys.argv[2]).read_bytes()).hexdigest();v['status']='Accepted'
with tempfile.NamedTemporaryFile(mode='w',dir=p.parent,delete=False) as f:
 json.dump(v,f,indent=2);temporary=f.name
os.replace(temporary,p)
PY
            xcrun stapler validate "${package}"
            spctl --assess --type install --verbose=2 "${package}"
            python3 - "${package}" <<'PY'
import hashlib,sys
from pathlib import Path
p=Path(sys.argv[1]);sums=p.parent/'SHA256SUMS'
if sums.exists():
 rows=[r for r in sums.read_text().splitlines() if not r.endswith('  '+p.name)]
 rows.append(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name)
 sums.write_text('\n'.join(rows)+'\n')
PY
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
