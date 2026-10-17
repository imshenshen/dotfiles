#!/usr/bin/env bash
# Tests the patched frontend against in-memory preferences, not the user's domain.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
xcrun swiftc -parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${root}/rime/.build/squirrel/sources/InputSource.swift" "${root}/rime/tests/input_source_migration_test.swift" \
  -o "${root}/rime/.build/voice/input-source-migration-test"
"${root}/rime/.build/voice/input-source-migration-test"
