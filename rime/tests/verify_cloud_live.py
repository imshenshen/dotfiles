"""Public-sample end-to-end provider checks using the production native plugin.

Run only with an isolated directory, never the live input-method user directory.
"""
import sys
import time
from pathlib import Path
from rime_harness import Rime, pump

rime = Rime(Path(sys.argv[1]), Path(sys.argv[2]))
session = rime.session()
for code in ['zhongguo', 'xinzhishengchanli', 'heishenhuawukong']:
    rime.clear(session)
    started = time.monotonic()
    rime.type(session, code)
    input_ms = round((time.monotonic() - started) * 1000)
    rime.snapshot(session) # Force creation of the frontend's candidate page.
    notification_offset = len(rime.notifications)
    pump(1.8)
    snapshots = []
    # Read four pages to inspect interleaved cloud positions, not just page one.
    for page in range(4):
        snapshots.extend(rime.snapshot(session)['candidates'])
        rime.key(session, 0xff56, 0) # PageDown
    unique = dict(snapshots)
    mask = 0
    for comment in unique.values():
        if comment.startswith('\ue000') and '\ue001' in comment:
            mask |= int(comment[1:comment.index('\ue001')])
    providers = {name for bit, name in [(1, '搜狗'), (2, 'Google'), (4, '百度')] if mask & bit}
    refreshed = any(kind == b'property' and value.startswith(b'_refresh_ui=')
                    for _, kind, value in rime.notifications[notification_offset:])
    print(dict(input=code, input_ms=input_ms, providers=sorted(providers),
               refreshed=refreshed, candidates=list(unique.items())[:16]), flush=True)
    assert refreshed, 'Production provider did not refresh within its deadline'
    assert '搜狗' in providers, 'No full-match Sogou candidate returned'
    assert not rime.commit(session)
rime.destroy(session)
pump(.1)
rime.finalize()
print('PASS: production network adapter -> cache -> Rime candidates -> _refresh_ui, using public samples only')
