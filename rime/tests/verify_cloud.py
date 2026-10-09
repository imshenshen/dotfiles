"""Deterministic async integration checks against actual Rime + a test-only plugin.

Usage: python3 verify_cloud.py /tmp/deployed-test-dir Squirrel.app test-plugin.dylib
"""
import ctypes as C
import json
import sys
import time
from pathlib import Path
from rime_harness import Rime, pump

root, app, plugin = map(Path, sys.argv[1:4])
assert 'test' in plugin.name
phrase_file = root / 'custom_phrase.txt'
original = phrase_file.read_bytes()
phrase_file.write_bytes(original + '\n自定义中国\tzhongguo\t1000\n'.encode())
rime = Rime(root, app, plugin)
fixture = rime.cloud.CloudTestFixture
fixture.argtypes = [C.c_char_p, C.c_char_p, C.c_char_p, C.c_int, C.c_bool]
fixture.restype = None
requests = rime.cloud.CloudTestRequests
requests.argtypes = [C.c_char_p, C.c_char_p]
requests.restype = C.c_int
reset = rime.cloud.CloudTestReset
reset.argtypes = []
reset.restype = None


def respond(code, sogou, google, delay=20, success=True):
    for provider, words in [('sogou', sogou), ('google', google)]:
        fixture(provider.encode(), code.encode(), json.dumps(words).encode(), delay, success)


def count(provider, code):
    return requests(provider.encode(), code.encode())


def words(session):
    return [text for text, comment in rime.snapshot(session)['candidates']]


session = rime.session()
phrase_file.write_bytes(original)
reset()
respond('zhongguo', ['搜狗一', '搜狗二'], ['谷歌一', '谷歌二'], delay=30)
start = time.monotonic()
rime.type(session, 'zhongguo')
assert time.monotonic() - start < .5, 'Input must not wait for network'
assert words(session)[:2] == ['自定义中国', '中国'], words(session)
pump(.08)
assert count('sogou', 'zhongguo') == 0
pump(.2)
assert count('sogou', 'zhongguo') == count('google', 'zhongguo') == 1
assert words(session)[:4] == ['自定义中国', '中国', '搜狗一', '谷歌一'], words(session)
assert any(kind == b'property' and value.startswith(b'_refresh_ui=') for _, kind, value in rime.notifications)
print('PASS: debounce, parallel providers, custom-first interleaving, real engine/frontend notification')

# Short Wubi input, disabled cloud, and ASCII never query.
rime.clear(session)
rime.type(session, 'niha')
pump(.2)
assert count('sogou', 'niha') == count('google', 'niha') == 0
rime.clear(session)
rime.option(session, b'cloud_pinyin', 0)
rime.type(session, 'nihao')
pump(.2)
assert count('sogou', 'nihao') == 0
rime.clear(session)
rime.option(session, b'cloud_pinyin', 1)
print('PASS: four-code Wubi and local-only switch do not query')

# Re-enabling before or after the debounce deadline must resume the same input.
rime.option(session, b'cloud_pinyin', 0)
respond('zhishi', ['搜狗知识'], ['谷歌知识'], delay=10)
rime.type(session, 'zhishi')
pump(.2)
assert count('sogou', 'zhishi') == 0
rime.option(session, b'cloud_pinyin', 1)
pump(.25)
assert count('sogou', 'zhishi') == 1 and '搜狗知识' in words(session)
rime.clear(session)
print('PASS: enabling cloud resumes a composition that was typed offline')

# Reuse cache immediately after editing, without another network request.
rime.type(session, 'zhongguo')
assert words(session)[:4] == ['自定义中国', '中国', '搜狗一', '谷歌一']
pump(.2)
assert count('sogou', 'zhongguo') == 1
rime.clear(session)
respond('nihaoshijie', ['旧输入云词'], ['旧输入谷歌'], delay=300)
rime.type(session, 'nihaoshijie')
pump(.18)
assert count('sogou', 'nihaoshijie') == 1
rime.clear(session)
rime.type(session, 'zhongguo')
pump(.4)
assert '旧输入云词' not in words(session)
rime.clear(session)
rime.type(session, 'nihaoshijie')
assert '旧输入云词' in words(session)
assert count('sogou', 'nihaoshijie') == 1
print('PASS: edited input rejects stale UI updates but reuses the finished result from cache')

# Freeze the visible menu once the user starts navigating it.
rime.clear(session)
respond('rengongzhineng', ['迟到搜狗'], ['迟到谷歌'], delay=300)
rime.type(session, 'rengongzhineng')
pump(.18)
rime.key(session, 0xff54, 0) # Down
before = rime.snapshot(session)
pump(.4)
assert rime.snapshot(session) == before
rime.clear(session)
rime.type(session, 'rengongzhineng')
assert '迟到搜狗' in words(session)
print('PASS: navigation freezes candidate positions while delayed responses populate cache')

# Coalesce a pending request shared by two distinct engine sessions.
rime.clear(session)
other = rime.session()
respond('heishenhuawukong', ['搜狗悟空'], ['谷歌悟空'], delay=300)
rime.type(session, 'heishenhuawukong')
rime.type(other, 'heishenhuawukong')
pump(.2)
assert count('sogou', 'heishenhuawukong') == count('google', 'heishenhuawukong') == 1
rime.destroy(other) # A completion must not touch this destroyed engine.
pump(.4)
assert '搜狗悟空' in words(session)
print('PASS: in-flight coalescing across sessions and safe session destruction')

# Complete cloud-only selections persist in an independent native user dictionary.
rime.clear(session)
respond('damoxing', ['云候选学习测试'], ['大模型'], delay=10)
rime.type(session, 'damoxing')
pump(.25)
menu = words(session)
assert '云候选学习测试' in menu, menu
index = menu.index('云候选学习测试')
assert index < 4
rime.key(session, ord(str(index + 1)), 0)
assert rime.commit(session) == '云候选学习测试'
rime.clear(session)
rime.option(session, b'cloud_pinyin', 0)
rime.type(session, 'damoxing')
assert '云候选学习测试' in words(session), words(session)
print('PASS: selected cloud word remains available offline through independent user dictionary')

rime.clear(session)
rime.option(session, b'cloud_pinyin', 1)
respond('nihao', ['搜狗你好'], ['你好'], delay=10)
rime.type(session, 'zznihao')
pump(.25)
assert count('sogou', 'nihao') == 1 and count('sogou', 'zznihao') == 0
assert '搜狗你好' in words(session)
assert len(words(session)) == len(set(words(session)))
print('PASS: explicit zz prefix is excluded from requests and duplicate words are removed')

# A failed provider backs off independently; the other provider still succeeds.
rime.clear(session)
fixture(b'sogou', b'xinzhishengchanli', b'[]', 10, False)
fixture(b'google', b'xinzhishengchanli', json.dumps(['谷歌新质']).encode(), 10, True)
rime.type(session, 'xinzhishengchanli')
pump(.25)
assert '谷歌新质' in words(session)
rime.clear(session)
rime.type(session, 'xinzhishengchanli')
pump(.25)
assert count('sogou', 'xinzhishengchanli') == 1
assert count('google', 'xinzhishengchanli') == 1
print('PASS: failed provider backs off independently; successful provider uses its cache')

rime.destroy(session)
pump(.1)
rime.finalize()
print('PASS: all deterministic cloud integration checks')
