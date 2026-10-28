"""Verify direct ASCII punctuation and /fh, /bq, /mac, /gif through librime.

The app is expected to hand the exact raw input to the native palette. This
suite only covers the Rime side: literal punctuation is committed immediately
and the slash triggers stay raw with their normal candidate lists.
"""
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from rime_harness import Rime

repo = Path(__file__).resolve().parents[2]
app = Path(sys.argv[1]).resolve()
shared = app / 'Contents/SharedSupport'
assert (app / 'Contents/MacOS/rime_deployer').exists()
assert (shared / 'symbols.yaml').exists()

PAGE_DOWN = 0xff56
SCHEMAS = ('wubi86', 'luna_pinyin_simp', 'rime_frost')


def stage_shared(root, app):
    """Overlay the repository's distributable data on the installed app.

    The installed Squirrel may come from an earlier package, so its rime_frost
    schema is not a valid stand-in for the configuration being verified.
    """
    stage = root / 'shared'
    stage.mkdir()
    installed = app / 'Contents/SharedSupport'
    for child in installed.iterdir():
        if child.name == 'build':
            continue
        (stage / child.name).symlink_to(child, target_is_directory=child.is_dir())
    for child in (repo / 'rime/distribution/data').iterdir():
        target = stage / child.name
        if target.is_symlink() or target.exists():
            target.unlink()
        target.symlink_to(child, target_is_directory=child.is_dir())
    return stage


def deploy(root, shared):
    for name in ('default.custom.yaml', 'squirrel.custom.yaml', 'wubi86.custom.yaml',
                 'rime_frost.custom.yaml', 'luna_pinyin_simp.custom.yaml',
                 'wubi86_pinyin.schema.yaml', 'custom_phrase.txt'):
        source = repo / 'rime' / name
        if source.exists():
            shutil.copy2(source, root / name)
    (root / 'lua').mkdir(exist_ok=True)
    for lua in ('wubi_pinyin_router.lua', 'slash_literal.lua'):
        source = repo / 'rime/lua' / lua
        if source.exists():
            shutil.copy2(source, root / 'lua' / lua)
    result = subprocess.run(
        [str(app / 'Contents/MacOS/rime_deployer'), '--build', str(root), str(shared), str(root / 'build')],
        text=True, capture_output=True)
    if result.returncode != 0:
        raise SystemExit('deployment failed:\n' + result.stdout + result.stderr)
    assert (root / 'build/wubi86.schema.yaml').exists()
    assert (root / 'build/rime_frost.schema.yaml').exists()
    assert (root / 'build/luna_pinyin_simp.schema.yaml').exists()


def raw(r, session):
    return r.snapshot(session)['preedit']


def candidates_all_pages(r, session):
    result, seen_pages = [], set()
    while True:
        context = r.snapshot(session)
        page = (context['page_no'], context['num_candidates'])
        assert page not in seen_pages, 'pagination did not advance'
        seen_pages.add(page)
        result.extend(text for text, _ in context['candidates'])
        if context['last_page']:
            break
        assert r.key(session, PAGE_DOWN, 0)
        assert not r.commit(session)
    return result


with tempfile.TemporaryDirectory(prefix='rime-slash-') as tmp:
    root = Path(tmp)
    shared = stage_shared(root, app)
    deploy(root, shared)
    r = Rime(root, app, shared=shared)
    try:
        for schema in SCHEMAS:
            for full_shape in (False, True):
                s = r.session(False, schema)
                r.option(s, b'full_shape', int(full_shape))
                for character in '`#%*':
                    r.clear(s)
                    assert r.key(s, ord(character), 0), (schema, character)
                    committed = r.commit(s)
                    assert committed == character, (schema, full_shape, character, committed)
                    context = r.snapshot(s)
                    assert not context['candidates'], (schema, full_shape, character, context)
                    assert context['preedit'] == '', (schema, full_shape, character, context)
                # Typing # requires Shift+3 on a US layout. The literal
                # processor sits after ascii_composer, so the Shift release
                # must not be mistaken for a lone-Shift mode toggle.
                s_shift = r.session(False, schema)
                r.clear(s_shift)
                r.key(s_shift, 0xffe1, 1)  # Shift_L down
                assert r.key(s_shift, ord('#'), 1)
                assert r.commit(s_shift) == '#'
                r.key(s_shift, 0xffe1, 1 | (1 << 30))  # Shift_L release
                assert r.key(s_shift, ord('a'), 0), (schema, 'Shift+3 toggled English mode')
                assert raw(r, s_shift) == 'a', (schema, raw(r, s_shift))
                r.destroy(s_shift)

                r.clear(s)
                for character in '/fh':
                    assert r.key(s, ord(character), 0)
                    assert not r.commit(s)
                assert raw(r, s) == '/fh', (schema, raw(r, s))
                # rime_frost's own symbol translator is incomplete in the
                # headless harness (upstream Lua helpers are unavailable).
                # The native palette only needs the raw trigger, which is
                # covered for every schema. The 158-item preset is verified
                # against the schemas that translate it end-to-end.
                if schema != 'rime_frost':
                    symbols = candidates_all_pages(r, s)
                    assert len(symbols) == len(set(symbols)) == 158, (schema, len(symbols))
                    assert all(len(value) == 1 and not (0x20 <= ord(value) <= 0x7e) for value in symbols), schema
                r.clear(s)
            print(f'PASS: {schema}: literal ` # % * in half/full shape; /fh remains raw for the native palette')

        # Ordinary slash and /gif must stay raw input for the app to inspect.
        for schema in SCHEMAS:
            s = r.session(False, schema)
            assert r.key(s, ord('/'), 0)
            assert not r.commit(s)
            r.clear(s)
            for character in '/gif':
                assert r.key(s, ord(character), 0)
                assert not r.commit(s)
            assert raw(r, s) == '/gif', (schema, raw(r, s))
            r.clear(s)
        print('PASS: ordinary / and raw /gif remain available for the native palette in all schemas')

        wubi = r.session(False, 'wubi86')
        for trigger in ('/fh', '/bq', '/mac'):
            r.clear(wubi)
            for character in trigger:
                assert r.key(wubi, ord(character), 0)
                assert not r.commit(wubi)
            assert raw(r, wubi) == trigger
            context = r.snapshot(wubi)
            assert context['candidates'], (trigger, context)
        print('PASS: wubi86 keeps /fh plus its /bq and /mac categories')

        # luna used backtick for stroke lookup; the literal commit is the
        # documented trade-off that makes the direct-ASCII rule consistent.
        luna = r.session(False, 'luna_pinyin_simp')
        r.option(luna, b'full_shape', 0)
        assert r.key(luna, ord('`'), 0)
        assert r.commit(luna) == '`'
        print('PASS: luna_pinyin_simp backtick commits literally; stroke reverse lookup is disabled by design')
    finally:
        r.finalize()

print('PASS: slash Rime configuration (direct ASCII, /fh raw trigger and preset count, /bq, /mac, /gif, luna trade-off)')
