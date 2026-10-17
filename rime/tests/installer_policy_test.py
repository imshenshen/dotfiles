"""Validate the real distribution metadata, before or after PKG expansion."""
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]/'distribution/Distribution'
root = ET.parse(path).getroot()
assert root.tag == 'installer-gui-script'
for element in root.iter():
    assert element.get('onConclusion') not in ('RequireLogout','RequireRestart','RecommendRestart'), element.attrib
    assert element.get('postinstall-action') not in ('logout','restart'), element.attrib
refs = [e for e in root.findall('pkg-ref') if e.text and e.text.strip()]
assert len(refs) == 1 and refs[0].get('id') == 'im.rime.inputmethod.Squirrel'
# productbuild rewrites an embedded component URL to a XAR fragment.
assert refs[0].text.strip() in ('Squirrel-component.pkg', '#Squirrel-component.pkg')
print('PASS: installer requires neither logout nor restart')

# Prevent recurrence of the confirmed unsafe install/build side effects.
project = Path(__file__).resolve().parents[1]
postinstall = (project/'distribution/scripts/postinstall').read_text()
assert 'defaults write com.apple.HIToolbox' not in postinstall
assert '--select-input-source' not in postinstall
assert '--repair-input-source' not in postinstall
assert 'lsregister' not in postinstall and 'killall' not in postinstall and '--quit' not in postinstall
assert postinstall.index('pkgutil --pkg-info') < postinstall.index('--register-input-source')
assert 'exit 0' in postinstall[postinstall.index('pkgutil --pkg-info'):postinstall.index('--register-input-source')]
assert 'Contents/Helpers/SourceRecovery" --prepare' in postinstall
assert 'SourceRecovery' in (project/'tools/package_squirrel.sh').read_text()
frontend = project/'.build/squirrel/Sources/SquirrelApplicationDelegate.swift'
if frontend.exists(): assert 'retireLegacyDuplicate' not in frontend.read_text()
assert 'open "${installed_app}"' not in (project/'tools/install_squirrel.sh').read_text().split('Installed source commit:')[-1]
for file in ('tools/build_squirrel.sh', 'tools/prepare_release_data.sh'):
    script = (project/file).read_text()
    assert '../MacOS/Squirrel --build' not in script
    assert '../MacOS/rime_deployer --build' in script
print('PASS: installer preserves native switching/consent, and packaging uses a headless deployer')
