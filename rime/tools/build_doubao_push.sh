#!/usr/bin/env bash
# Build the external Doubao dictionary push helper.
#
# The helper must live outside Squirrel.app: the release app is signed with
# hardened runtime/library validation, while the helper needs to dlopen the
# vendor OimeEngine.framework signed by a different team. This script builds,
# ad-hoc signs (without --options runtime), self-tests, and installs the helper
# into the user's Application Support directory. It does not touch Squirrel.app
# or its signing.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="${root}/rime/native/doubao-dictionary/doubao_push.cpp"
engine="/Library/Input Methods/DoubaoIme.app/Contents/Frameworks/OimeEngine.framework/Versions/A/OimeEngine"
frameworks="/Library/Input Methods/DoubaoIme.app/Contents/Frameworks"
install_dir="${HOME}/Library/Application Support/Squirrel/DoubaoPush"
install_path="${install_dir}/doubao_push"

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "doubao_push: macOS arm64 is required" >&2
  exit 1
fi
if [[ ! -f "${engine}" ]]; then
  echo "doubao_push: Doubao input method is not installed" >&2
  exit 1
fi

mkdir -p -m 700 "${install_dir}"
work="$(mktemp -d "${install_dir}/build-XXXXXX")"
chmod 700 "${work}"
trap 'rm -rf "${work}"' EXIT

xcrun clang++ -std=c++17 -O2 -arch arm64 -mmacosx-version-min=13.0 \
  -framework CoreFoundation \
  -Wl,-rpath,"${frameworks}" \
  "${source_file}" -o "${work}/doubao_push"

codesign --force --sign - "${work}/doubao_push"
codesign --verify --strict "${work}/doubao_push"

# Selftest uses a synthetic dictionary under Application Support and never
# touches the live Doubao account.
"${work}/doubao_push" --selftest >/dev/null
"${work}/doubao_push" --version

install -m 700 "${work}/doubao_push" "${install_path}"
"${install_path}" --version
echo "installed ${install_path}"
