#!/usr/bin/env bash
# Offline: URLProtocol injects responses; no credentials or cloud request.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "${root}/rime/.build/voice"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${root}/rime/native/voice/VoiceRewrite.swift" "${root}/rime/tests/voice_rewrite_test.swift" \
  -o "${root}/rime/.build/voice/voice-rewrite-test"
"${root}/rime/.build/voice/voice-rewrite-test"
