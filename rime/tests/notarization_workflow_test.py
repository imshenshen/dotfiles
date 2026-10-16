"""Offline notary workflow tests. Fake Apple tools, no credentials or uploads."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).resolve().parents[1] / 'tools/notarize_squirrel.sh'
with tempfile.TemporaryDirectory(prefix='rime-notary-test-') as folder:
    root = Path(folder); binaries = root/'bin'; binaries.mkdir()
    fake = binaries/'fake-tool'
    fake.write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
name=Path(sys.argv[0]).name;a=sys.argv[1:];root=Path(os.environ['NOTARY_TEST_ROOT'])
if name=='xcrun':
 if a[:2]==['notarytool','submit']:
  if os.environ.get('NOTARY_TEST_FAIL')=='1':sys.exit(69)
  count=int((root/'submits').read_text())+1 if (root/'submits').exists() else 1
  (root/'submits').write_text(str(count));print(json.dumps({'id':'mock-'+str(count)}))
 elif a[:2]==['notarytool','info']:print(json.dumps({'status':'Accepted'}))
 elif a[:2]==['stapler','staple']:
  p=Path(a[2]);data=p.read_bytes()
  if not data.endswith(b'|ticket'):p.write_bytes(data+b'|ticket')
 elif a[:2]==['stapler','validate']:assert Path(a[2]).read_bytes().endswith(b'|ticket')
 else:sys.exit(2)
elif name=='spctl':assert Path(a[-1]).read_bytes().endswith(b'|ticket')
elif name!='pkgutil':sys.exit(2)
''')
    fake.chmod(0o755)
    for name in ('xcrun','spctl','pkgutil'):
        (binaries/name).symlink_to(fake.name)
    env = dict(os.environ, PATH=str(binaries)+os.pathsep+os.environ['PATH'], NOTARY_TEST_ROOT=str(root))
    package = root/'test.pkg'; package.write_bytes(b'build-one')
    (root/'SHA256SUMS').write_text('old  test.pkg\nother  untouched.pkg\n')
    def run(path=package, environment=env):
        return subprocess.run(['bash',str(script),str(path),'mock-profile'],env=environment,capture_output=True,text=True)
    for _ in range(2):
        result=run(); assert result.returncode==0,result.stderr
        assert 'Gatekeeper validation passed' in result.stdout
    assert (root/'submits').read_text()=='1','Stapled package was uploaded twice'
    state=json.loads((root/'test.notarization.json').read_text())
    digest=hashlib.sha256(package.read_bytes()).hexdigest()
    assert state['stapled_package_sha256']==digest
    assert f'{digest}  test.pkg' in (root/'SHA256SUMS').read_text()
    assert 'other  untouched.pkg' in (root/'SHA256SUMS').read_text()
    package.write_bytes(b'build-two')
    assert run().returncode==0
    assert (root/'submits').read_text()=='2','A different package must get a new submission'
    failed=root/'failed.pkg'; failed.write_bytes(b'failed-upload')
    assert run(failed,dict(env,NOTARY_TEST_FAIL='1')).returncode!=0
    assert not (root/'failed.notarization.json').exists()
    assert not list(root.glob('*.submission.*'))
print('PASS: offline submit/staple/validate flow, resume without duplicate upload, new build isolation, final checksums and failed upload cleanup')
