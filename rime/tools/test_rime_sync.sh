#!/usr/bin/env bash
# Offline sync regressions. The live test is opt-in and reads credentials from
# the environment; no credential is stored in the repository.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${root}/rime/.build/voice"
src="${root}/rime/native/voice"
tests="${root}/rime/tests"
mkdir -p "${out}"
flags=(-parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache")
xcrun swiftc "${flags[@]}" "${src}/VoiceTextFormatter.swift" "${src}/RimeSync.swift" \
  "${src}/RimeDictionarySync.swift" "${src}/RimeSyncService.swift" \
  "${tests}/rime_sync_test.swift" -o "${out}/rime-sync-test"
"${out}/rime-sync-test"
if [[ -n "${RIME_SYNC_AK:-}" && -n "${RIME_SYNC_SK:-}" ]]; then
  xcrun swiftc "${flags[@]}" "${src}/VoiceTextFormatter.swift" "${src}/RimeSync.swift" \
    "${src}/RimeDictionarySync.swift" "${src}/RimeSyncService.swift" \
    "${tests}/rime_sync_live.swift" -o "${out}/rime-sync-live-test"
  "${out}/rime-sync-live-test"
else
  echo "SKIP: live OSS test (set RIME_SYNC_AK and RIME_SYNC_SK to run)"
fi
