#!/usr/bin/env python3
"""Sign nested code inside-out with a single Developer ID. Never exports keys."""
import argparse, os, plistlib, subprocess
from pathlib import Path

p=argparse.ArgumentParser();p.add_argument('app',type=Path);p.add_argument('--identity',required=True);p.add_argument('--team',required=True)
a=p.parse_args();app=a.app.resolve();root=Path(__file__).resolve().parents[1]
assert app.name=='Squirrel.app' and (app/'Contents/MacOS/Squirrel').is_file()
# Do not alter a running installed input method or silently change permissions.
if str(app).startswith('/Library/') or str(app).startswith(str(Path.home()/'Library/Input Methods')):
 raise SystemExit('Sign a staged build, not the installed input method')

def run(*args):
 return subprocess.run(args,check=True,capture_output=True,text=True).stdout

def sign(target,audio=False,macho=True):
 ent=root/'native/signing'/('audio.entitlements' if audio else 'empty.entitlements')
 command=['codesign','--force','--sign',a.identity,'--timestamp']
 if macho: command+=['--options','runtime','--entitlements',str(ent)]
 if subprocess.run(['codesign','-d',str(target)],capture_output=True).returncode==0:
  command+=['--preserve-metadata=identifier']
 subprocess.run(command+[str(target)],check=True)

# Include binaries regardless of their filename, extension, or executable bit.
magic={bytes.fromhex(x) for x in ('feedface','cefaedfe','feedfacf','cffaedfe','cafebabe','bebafeca','cafebabf','bfbafeca')}
files=[]
scripts=[]
for f in app.rglob('*'):
 if f.is_file() and not f.is_symlink():
  with f.open('rb') as h: header=h.read(4)
  if header in magic:files.append(f)
  elif header.startswith(b'#!') and f.parent.name=='MacOS':scripts.append(f)
# Signing the main executable can validate its enclosing bundle's nested code.
# Sign sibling standalone helpers first, even when they have equal path depth.
for f in sorted(files,key=lambda x:(len(x.parts), x != app/'Contents/MacOS/Squirrel'),reverse=True):sign(f)
for f in scripts:sign(f,macho=False)
# Sign bundle seals after their inner code; symlinks in versioned frameworks are skipped.
bundles=[f for f in app.rglob('*') if f.is_dir() and not f.is_symlink() and f.suffix in ('.app','.xpc','.framework','.bundle')]
for bundle in sorted(bundles,key=lambda x:len(x.parts),reverse=True):sign(bundle,bundle.name=='RimeVoice.app')
sign(app,True)
subprocess.run(['codesign','--verify','--deep','--strict','--verbose=2',str(app)],check=True)
# Validate every binary's certificate identity, secure timestamp, runtime, and entitlements.
for f in files:
 result=subprocess.run(['codesign','-d','--verbose=4',str(f)],check=True,capture_output=True,text=True)
 detail=result.stderr
 assert f'TeamIdentifier={a.team}' in detail, str(f)
 assert 'Authority=Developer ID Application:' in detail, str(f)
 assert 'Timestamp=' in detail and '(runtime)' in detail,str(f)
 ent=subprocess.run(['codesign','-d','--entitlements',':-',str(f)],check=True,capture_output=True).stdout
 values=plistlib.loads(ent) if ent.strip() else {}
 assert not values.get('com.apple.security.get-task-allow'),str(f)
 assert not values.get('com.apple.security.cs.disable-library-validation'),str(f)
print(f'PASS: Developer ID, hardened runtime and timestamp verified on {len(files)} binaries; no debug or library-validation bypass entitlements')
for f in scripts:
 detail=subprocess.run(['codesign','-d','--verbose=4',str(f)],check=True,capture_output=True,text=True).stderr
 assert f'TeamIdentifier={a.team}' in detail and 'Timestamp=' in detail and 'Authority=Developer ID Application:' in detail,str(f)
print(f'PASS: {len(scripts)} executable scripts also use Developer ID and secure timestamps')
