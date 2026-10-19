#!/usr/bin/env bash
# Only enables bounded metadata diagnostics; never captures keys or document text.
set -euo pipefail
domain='im.rime.inputmethod.Squirrel.Voice'
case "${1:-}" in
  start)
    record='/Library/Input Methods/Squirrel.app/Contents/Resources/LocalBuild.plist'
    [[ "$(plutil -extract KeyboardSpacingDiagnostics raw "${record}" 2>/dev/null || true)" == 1 ]] || {
      echo 'Install the keyboard-spacing diagnostic build first.' >&2; exit 1;
    }
    debug_until=$(( $(date +%s) + 300 ))
    defaults write "${domain}" keyboardSpacingDiagnosticsUntil -float "${debug_until}"
    echo 'Enabled for 5 minutes, at most 240 iTerm2 metadata records. Reproduce once, then run collect and stop.'
    ;;
  collect)
    /usr/bin/log show --last 10m --style compact --info \
      --predicate 'subsystem == "im.rime.inputmethod.Squirrel" AND category == "KeyboardSpacing"'
    ;;
  stop)
    defaults delete "${domain}" keyboardSpacingDiagnosticsUntil 2>/dev/null || true
    echo 'Disabled keyboard spacing diagnostics.'
    ;;
  *) echo 'Usage: bash rime/tools/debug_keyboard_spacing.sh start|collect|stop' >&2; exit 2 ;;
esac
