#!/usr/bin/env bash
# Run in the user's terminal: notarytool prompts securely and stores credentials
# in Keychain. Only the profile name is written to the ignored local config.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
python3 - "${root}" "${1:-squirrel-notary}" <<'PY'
import json, os, pathlib, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1]); profile = sys.argv[2]
config = pathlib.Path(os.environ.get('SQUIRREL_SIGN_CONFIG', str(root/'rime/.build/signing/release.json')))
if not sys.stdin.isatty():
    # Python source arrives through stdin; the actual interactive session uses
    # the controlling terminal rather than the heredoc source pipe.
    try:
        terminal = open('/dev/tty', 'rb', buffering=0)
    except OSError:
        raise SystemExit('Run this script interactively in your own macOS terminal.')
else:
    terminal = sys.stdin
values = json.loads(config.read_text())
team = values.get('team')
if not team or not profile.strip() or '\n' in profile or '\r' in profile:
    raise SystemExit('Missing signing Team ID or invalid profile name')
print('Enter your developer Apple Account and app-specific password in the terminal prompts; never paste the password into chat.', flush=True)
result = subprocess.run(['xcrun', 'notarytool', 'store-credentials', profile, '--team-id', team], stdin=terminal)
if result.returncode != 0:
    raise SystemExit('Notary authentication did not complete; the previous release configuration was preserved.')
values['notary_profile'] = profile
with tempfile.NamedTemporaryFile(mode='w', dir=config.parent, prefix='.notary-config-', delete=False) as file:
    json.dump(values, file, indent=2); file.write('\n'); temporary = pathlib.Path(file.name)
try:
    os.chmod(temporary, 0o600)
    os.replace(temporary, config)
finally:
    temporary.unlink(missing_ok=True)
print('PASS: validated Keychain profile configured. Future build_squirrel.sh runs will sign, notarize, staple and verify Gatekeeper.')
PY
