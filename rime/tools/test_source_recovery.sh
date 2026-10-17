#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "${root}/rime/.build/source-recovery"
xcrun swiftc -swift-version 5 -parse-as-library -DSOURCE_RECOVERY_TEST \
  -module-cache-path "${root}/rime/.build/swift-module-cache" \
  "${root}/rime/native/installer/SourceRecovery.swift" "${root}/rime/tests/source_recovery_test.swift" \
  -o "${root}/rime/.build/source-recovery/tests"
"${root}/rime/.build/source-recovery/tests"
python3 "${root}/rime/tests/installer_policy_test.py"
