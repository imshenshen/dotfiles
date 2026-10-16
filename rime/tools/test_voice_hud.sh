#!/usr/bin/env bash
# Requires a macOS GUI session. Shows only this test's own short-lived panels;
# uses injected input anchors, no microphone, other-app AX reads or clipboard.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "${root}" <<'PY'
import pathlib, re, subprocess, sys
root = pathlib.Path(sys.argv[1])
build = (root/'rime/tools/build_voice.sh').read_text()
bridge = build.split('-emit-library', 1)[1].split('-lz', 1)[0]
files = re.findall(r'"\$\{src\}/([^"\n]+)"', bridge)
assert 'VoiceViews.swift' in files and 'VoiceHUDPlacement.swift' in files
out = root/'rime/.build/voice/voice-hud-behavior-test'
subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library', '-module-cache-path',
 str(root/'rime/.build/swift-module-cache'), *[str(root/'rime/native/voice'/f) for f in files],
 str(root/'rime/tests/voice_hud_behavior_test.swift'), '-lz', '-o', str(out)], check=True)
subprocess.run([str(out)], check=True)
PY
