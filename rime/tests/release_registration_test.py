"""Real macOS regression: data compilation must not register temporary IMEs.

Run in the logged-in user's GUI session with a built Squirrel.app. Does not
install/enable/select an input source or read user dictionary/history contents.
"""
from collections import Counter
from pathlib import Path
import subprocess
import sys
import tempfile

project = Path(__file__).resolve().parents[2]
app = Path(sys.argv[1]).resolve()
registry = '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister'

def registered_paths():
    dump = subprocess.run([registry, '-dump'], check=True, capture_output=True, text=True).stdout
    paths = Counter()
    path = None
    for line in dump.splitlines():
        if line.startswith('path:'):
            path = line.split(':', 1)[1].strip().rsplit(' (0x', 1)[0]
        if line.startswith('identifier:') and line.split(':', 1)[1].strip() == 'im.rime.inputmethod.Squirrel':
            if path:
                paths[path] += 1
    return paths

before = registered_paths()
with tempfile.TemporaryDirectory(prefix='registration-test-', dir=project/'rime/.build') as directory:
    temporary = Path(directory)
    try:
        for index in range(2):
            staged = temporary/str(index)/'Squirrel.app'
            staged.parent.mkdir()
            subprocess.run(['/usr/bin/ditto', str(app), str(staged)], check=True)
            subprocess.run(['bash', str(project/'rime/tools/prepare_release_data.sh'), str(staged)],
                           check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            assert (staged/'Contents/SharedSupport/build/wubi86.schema.yaml').exists()
            assert (staged/'Contents/SharedSupport/build/rime_frost.table.bin').exists()
            added = registered_paths() - before
            assert not added, f'Data build registered {sum(added.values())} unwanted input-method entries'
    finally:
        # If a future regression registered our own fixtures, undo only those
        # temporary registrations before deleting the test directories.
        for path in registered_paths() - before:
            if Path(path).is_relative_to(temporary):
                subprocess.run([registry, '-u', path], check=False, capture_output=True)
assert registered_paths() == before, 'Input-method registry changed during packaging test'
print('PASS: two independent release data builds leave the real input-method registry unchanged')
