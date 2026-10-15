"""Fifth-key commits and pinyin protection against a deployed isolated backend."""
import sys
from pathlib import Path
from rime_harness import Rime

root, app, plugin = map(Path, sys.argv[1:4])
phrase_file = root / 'custom_phrase.txt'
original = phrase_file.read_bytes()
phrase_file.write_bytes(original + '\n自定义顶字\tglll\t1000\n'.encode())
try:
    r = Rime(root, app, plugin)
    s = r.session(False)
finally:
    phrase_file.write_bytes(original)

def keys(text):
    commits = []
    for c in text:
        assert r.key(s, ord(c), 0)
        word = r.commit(s)
        if word:
            commits.append(word)
    return commits

assert keys('ggll') == []
assert r.snapshot(s)['candidates'][0][0] == '一'
assert keys('g') == ['一']
assert r.snapshot(s)['preedit'] == 'g'
r.clear(s)
assert keys('ggllggllg') == ['一', '一']
assert r.snapshot(s)['preedit'] == 'g'
r.clear(s)
assert keys('jjjjj') == ['日']
assert r.snapshot(s)['preedit'] == 'j'
print('PASS: no fourth-key commit; fifth-key and repeated Wubi commits retain next letter')
r.clear(s)
assert keys('glll') == []
assert r.snapshot(s)['candidates'][0][0] == '自定义顶字'
assert keys('g') == ['自定义顶字']
print('PASS: custom phrase stays first and commits through normal learning hooks')

for code, word in [('ni', '你'), ('mima', '密码'), ('mimi', '秘密'), ('mama', '妈妈'), ('nihao', '你好'), ('zhongguo', '中国'),
                   ('zhishi', '知识'), ('rengongzhineng', '人工智能'), ('shijie', '世界'),
                   ('shurufa', '输入法'), ('zhongwen', '中文'),
                   ('menghuanmonizhan', '梦幻模拟战'), ('zznihao', '你好')]:
    r.clear(s)
    assert keys(code) == [], code
    assert word in [w for w, _ in r.snapshot(s)['candidates']], (code, r.snapshot(s))
r.clear(s)
assert keys('aaaaa') == []  # Both aaaa Wubi and a+a+a+a pinyin are valid: protect pinyin.
assert '啊' in r.snapshot(s)['candidates'][0][0]
print('PASS: short pinyin, complete z pinyin, zz lookup and ambiguous four-code protection')

r.clear(s)
keys('ggll')
r.key(s, 0xff51, 0)  # insertion inside the code
assert keys('a') == []
r.clear(s)
keys('ggll')
r.key(s, 0xff54, 0)  # deliberate candidate navigation
assert keys('g') == []
r.clear(s)
keys('nihao')
r.key(s, 0xff08, 0)
assert not r.commit(s)
assert '〔拼音〕' not in r.snapshot(s)['preedit']
assert keys('o') == []
assert r.snapshot(s)['candidates'][0][0] == '你好'
print('PASS: caret editing, manual selection and backspace do not accidentally commit')
r.clear(s)
keys('niha')
index = [w for w, _ in r.snapshot(s)['candidates']].index('你')
r.key(s, ord(str(index + 1)), 0)
assert not r.commit(s)
assert r.snapshot(s)['candidates'][0][0] == '哈'
r.key(s, ord(' '), 0)
assert r.commit(s) == '你哈'
print('PASS: partial selection from short mixed pinyin retains pinyin for the tail')
r.finalize()
