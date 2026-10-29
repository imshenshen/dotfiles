#!/usr/bin/env bash
# Header-only cloud candidate core: ranking, TTL/LRU cache and binary bounds.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${root}/rime/.build/cloud-core"
mkdir -p "${out}"
xcrun clang++ -std=c++17 -O2 -I "${root}/rime/native/cloud_pinyin" \
  "${root}/rime/tests/cloud_core_test.cc" -o "${out}/cloud-core-test"
"${out}/cloud-core-test"
