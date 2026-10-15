#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${root}/rime/.build/voice"
mkdir -p "${out}"
sources=("${root}/rime/native/voice/VoiceTranscript.swift" "${root}/rime/native/voice/DoubaoProtocol.swift")
xcrun swiftc -parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${sources[@]}" "${root}/rime/tests/doubao_protocol_test.swift" -lz -o "${out}/doubao-protocol-test"
"${out}/doubao-protocol-test"
xcrun swiftc -parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${sources[@]}" "${root}/rime/native/voice/DoubaoStream.swift" "${root}/rime/native/voice/VoiceEditing.swift" \
  "${root}/rime/tests/doubao_stream_test.swift" \
  -lz -o "${out}/doubao-stream-test"
port=18974
fixture="$(mktemp -d "${TMPDIR:-/tmp}/rime-doubao-test.XXXXXX")"
node "${root}/rime/tests/doubao_mock_server.mjs" "${port}" > "${fixture}/server.log" 2>&1 &
mock_pid=$!
mock_server_pid=""
trap 'if [[ -n "${mock_server_pid}" ]]; then kill "${mock_server_pid}" 2>/dev/null || true; fi; kill "${mock_pid}" 2>/dev/null || true; wait "${mock_pid}" 2>/dev/null || true; rm -rf "${fixture}"' EXIT
for attempt in {1..50}; do
  if /usr/bin/grep -q '^READY ' "${fixture}/server.log"; then mock_server_pid="$(awk '/^READY / {print $2; exit}' "${fixture}/server.log")"; break; fi
  if ! kill -0 "${mock_pid}" 2>/dev/null; then cat "${fixture}/server.log"; exit 1; fi
  sleep 0.1
done
"${out}/doubao-stream-test" "${port}"
