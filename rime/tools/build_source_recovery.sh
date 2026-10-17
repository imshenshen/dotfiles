#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${root}/rime/.build/source-recovery"
mkdir -p "${out}"
for arch in arm64 x86_64; do
    xcrun swiftc -swift-version 5 -parse-as-library -O -target "${arch}-apple-macos13.0" \
        -module-cache-path "${root}/rime/.build/swift-module-cache" \
        "${root}/rime/native/installer/SourceRecovery.swift" -o "${out}/recovery-${arch}"
done
lipo -create "${out}/recovery-arm64" "${out}/recovery-x86_64" -output "${out}/SourceRecovery"
