#!/usr/bin/env bash
# Offline regressions for the slash palette. No keychain, network or user defaults.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out="${root}/rime/.build/voice"
src="${root}/rime/native/voice"
tests="${root}/rime/tests"
mkdir -p "${out}"
flags=(-parse-as-library -module-cache-path "${root}/rime/.build/swift-module-cache")

xcrun swiftc "${flags[@]}" "${src}/SlashCommand.swift" "${tests}/slash_command_test.swift" \
  -o "${out}/slash-command-test"
"${out}/slash-command-test"

xcrun swiftc "${flags[@]}" "${src}/SlashSymbols.swift" "${src}/SlashSymbolData.swift" \
  "${tests}/slash_symbols_test.swift" -o "${out}/slash-symbols-test"
"${out}/slash-symbols-test"

xcrun swiftc "${flags[@]}" "${src}/GIFSearch.swift" "${tests}/gif_search_test.swift" \
  -o "${out}/gif-search-test"
"${out}/gif-search-test"

xcrun swiftc "${flags[@]}" "${src}/GIFSearch.swift" "${src}/GIFSearchService.swift" \
  "${src}/GIFClipboard.swift" "${tests}/gif_clipboard_test.swift" -o "${out}/gif-clipboard-test"
"${out}/gif-clipboard-test"

xcrun swiftc "${flags[@]}" "${src}/SlashCommand.swift" "${src}/SlashSymbols.swift" \
  "${src}/SlashSymbolData.swift" "${src}/GIFSearch.swift" "${src}/SlashPaletteWindow.swift" \
  "${tests}/slash_panel_test.swift" -o "${out}/slash-panel-test"
"${out}/slash-panel-test"

echo "PASS: slash palette offline suite"
