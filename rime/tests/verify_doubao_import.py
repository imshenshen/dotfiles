"""Offline candidate/commit test of the exact imported phrase representation."""
import sys
import tempfile
from pathlib import Path
from rime_harness import Rime

app = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/Library/Input Methods/Squirrel.app')
with tempfile.TemporaryDirectory(prefix='rime-doubao-import-') as directory:
    root = Path(directory)
    (root / 'custom_phrase.txt').write_text(
        '# synthetic import only\n松鼠桥接甲\tsongshuqiaojiejia\t1\n'
        '松鼠桥接乙\tsongshuqiaojieyi\t1\n', encoding='utf-8')
    engine = Rime(root, app)
    try:
        session = engine.session(False)
        for code, word in [('songshuqiaojiejia', '松鼠桥接甲'), ('songshuqiaojieyi', '松鼠桥接乙')]:
            engine.clear(session)
            engine.type(session, code)
            assert engine.snapshot(session)['candidates'][0][0] == word
            engine.key(session, ord(' '), 0)
            assert engine.commit(session) == word
        print('PASS: imported pinyin phrases are first candidates and commit correctly in the mixed Wubi schema; cloud disabled, isolated synthetic dictionary')
    finally:
        engine.finalize()
