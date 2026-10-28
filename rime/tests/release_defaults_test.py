"""Deploy packaged defaults in a fresh, isolated Rime directory, then test user overrides."""
import ctypes as C
import hashlib
import plistlib
import sys
import tempfile
from pathlib import Path
from rime_harness import Traits, Rime

app = Path(sys.argv[1]).resolve()
shared = app / 'Contents/SharedSupport'
for bundle in (app, app/'Contents/Helpers/RimeVoice.app'):
    info = plistlib.load(open(bundle/'Contents/Info.plist', 'rb'))
    assert isinstance(info.get('NSMicrophoneUsageDescription'), str) and info['NSMicrophoneUsageDescription'].strip(), f'Missing microphone purpose string: {bundle}'
print('PASS: both the input method and microphone helper have microphone permission descriptions')
with tempfile.TemporaryDirectory(prefix='rime-release-') as tmp:
    root = Path(tmp)
    lib = C.CDLL(str(app/'Contents/Frameworks/librime.1.dylib'), mode=C.RTLD_GLOBAL)
    lua = C.CDLL(str(app/'Contents/Frameworks/rime-plugins/librime-lua.dylib'), mode=C.RTLD_GLOBAL)
    cloud = C.CDLL(str(app/'Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib'), mode=C.RTLD_GLOBAL)
    def bind(name, args, result):
        f = getattr(lib, name); f.argtypes=args; f.restype=result; return f
    setup = bind('_Z9RimeSetupP13rime_traits_t', [C.POINTER(Traits)], None)
    initialize = bind('_Z14RimeInitializeP13rime_traits_t', [C.POINTER(Traits)], None)
    maintenance = bind('_Z20RimeStartMaintenancei', [C.c_int], C.c_int)
    join = bind('_Z25RimeJoinMaintenanceThreadv', [], None)
    deploy_config = bind('_Z20RimeDeployConfigFilePKcS0_', [C.c_char_p,C.c_char_p], C.c_int)
    finalize = bind('_Z12RimeFinalizev', [], None)
    modules = (C.c_char_p*4)(b'default',b'lua',b'cloud_pinyin',None)
    t = Traits(); t.data_size=C.sizeof(t)-C.sizeof(C.c_int)
    t.shared_data_dir=str(shared).encode(); t.user_data_dir=str(root).encode()
    t.distribution_code_name=b'Squirrel'; t.distribution_version=b'20261014.1'; t.log_dir=str(root).encode(); t.app_name=b'rime.release_defaults_test'; t.modules=modules; t.min_log_level=2
    setup(C.byref(t)); initialize(C.byref(t)); assert maintenance(1), "maintenance did not start"; join()
    assert deploy_config(b'squirrel.yaml', b'config_version')
    finalize()
    config_path=root/'build/default.yaml'
    if not config_path.exists(): config_path=shared/'build/default.yaml'
    config=config_path.read_text()
    assert 'schema: wubi86' in config and 'schema: rime_frost' in config
    assert 'cloud_pinyin_processor' in (shared/'build/wubi86.schema.yaml').read_text()
    r=Rime(root,app); s=r.session(False)
    for c in 'zhongguo': r.key(s,ord(c),0)
    assert '中国' in [w for w,_ in r.snapshot(s)['candidates']],r.snapshot(s)
    r.clear(s)
    for c in 'mima':
        r.key(s,ord(c),0)
        assert not r.commit(s), 'short pinyin unexpectedly committed'
    assert r.snapshot(s)['candidates'][0][0] == '密码',r.snapshot(s)
    r.clear(s)
    for c in 'ggll': r.key(s,ord(c),0); assert not r.commit(s)
    r.key(s,ord('g'),0); assert r.commit(s)=='一'
    r.finalize()
    print('PASS: clean profile needs no manual configuration import; mixed pinyin and fifth-code Wubi work')
    # Local configuration and dictionary remain authoritative after redeployment.
    (root/'custom_phrase.txt').write_text('本地保留词\tglll\t1000\n')
    (root/'mixed_user_dictionary.json').write_text('{"local-marker":true}')
    (root/'default.custom.yaml').write_text('patch:\n  "menu/page_size": 7\n  schema_list:\n    - schema: wubi86\n')
    preserved={p:p.read_bytes() for p in root.iterdir() if p.is_file() and p.name in ('custom_phrase.txt','mixed_user_dictionary.json','default.custom.yaml')}
    setup(C.byref(t)); initialize(C.byref(t)); assert maintenance(1), "maintenance did not start"; join(); finalize()
    assert all(p.read_bytes()==v for p,v in preserved.items())
    assert 'page_size: 7' in (root/'build/default.yaml').read_text()
    r=Rime(root,app); s=r.session(False)
    for c in 'glll': r.key(s,ord(c),0)
    assert r.snapshot(s)['candidates'][0][0]=='本地保留词',r.snapshot(s)
    r.finalize()
    print('PASS: redeployment keeps personal dictionary, metadata and config; personal override still works')

allowed={'provider','doubaoResource','doubaoAuthMode','shortcut','mixedSpacing','pauseMilliseconds'}
values=plistlib.load(open(app/'Contents/Resources/VoiceDefaults.plist','rb'))
assert values.keys() <= allowed
local = plistlib.load(open(app/'Contents/Resources/LocalBuild.plist', 'rb'))
assert local.get('SlashPaletteVersion') == 1
assert local.get('SlashPaletteNonactivating') is True
assert local.get('SlashSymbolCount') == 158
assert local.get('GIFSearchVersion') == 1
assert local.get('GIFClipboardNoAutoPaste') is True
assert (shared/'luna_pinyin_simp.custom.yaml').exists()
frost = (shared/'rime_frost.custom.yaml').read_text()
assert '"punctuator/symbols/+"' in frost
assert 'lua_processor@*slash_literal' in frost
for name in ('wubi86.custom.yaml', 'luna_pinyin_simp.custom.yaml'):
    assert 'lua_processor@*slash_literal' in (shared/name).read_text()
assert (shared/'lua/slash_literal.lua').exists()
assert (shared/'luna_pinyin_simp.custom.yaml').read_text().count('punctuator/full_shape') == 4
assert (shared/'luna_pinyin_simp.custom.yaml').read_text().count('punctuator/half_shape') == 4
assert not any(p.is_symlink() for p in shared.rglob('*'))
assert not any(p.name.endswith('.userdb') or p.name in ('mixed_user_dictionary.json','installation.yaml','user.yaml') for p in shared.rglob('*'))
assert (shared/'custom_phrase.txt').read_text().startswith('# Personal phrases')
print('PASS: slash/GIF defaults, nonactivating panel flags, luna/rime_frost patches and 158-symbol catalog are packaged; no personal dictionary, machine identity, learning database or credential settings')
