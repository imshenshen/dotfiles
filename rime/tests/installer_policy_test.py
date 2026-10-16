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
print('PASS: installer distribution keeps the correct component and requires neither logout nor restart')
