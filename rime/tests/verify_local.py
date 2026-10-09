"""Native librime regression checks. Pass an already deployed isolated directory in /tmp."""
import ctypes as C
import sys
import tempfile
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
assert ROOT.is_relative_to(Path('/tmp').resolve()) or ROOT.is_relative_to(Path(tempfile.gettempdir()).resolve()), 'Tests must not open the live user dictionary'
assert (ROOT/'build/wubi86.schema.yaml').exists(), 'Deploy the isolated test directory first'
APP=Path(sys.argv[2]) if len(sys.argv) > 2 else Path('/Library/Input Methods/Squirrel.app')
F=str(APP/'Contents/Frameworks')
r=C.CDLL(F+'/librime.1.dylib',mode=C.RTLD_GLOBAL)
lua=C.CDLL(F+'/rime-plugins/librime-lua.dylib',mode=C.RTLD_GLOBAL)
cloud_path=Path(sys.argv[3]) if len(sys.argv) > 3 else APP/'Contents/Frameworks/rime-plugins/librime-cloud-pinyin.dylib'
cloud=C.CDLL(str(cloud_path.resolve()),mode=C.RTLD_GLOBAL)
class Traits(C.Structure):
 _fields_=[('data_size',C.c_int)]+[(n,C.c_char_p) for n in ('shared_data_dir','user_data_dir','distribution_name','distribution_code_name','distribution_version','app_name')]+[('modules',C.POINTER(C.c_char_p)),('min_log_level',C.c_int)]+[(n,C.c_char_p) for n in ('log_dir','prebuilt_data_dir','staging_dir')]
class Composition(C.Structure):
 _fields_=[(n,C.c_int) for n in ('length','cursor_pos','sel_start','sel_end')]+[('preedit',C.c_char_p)]
class Candidate(C.Structure):
 _fields_=[('text',C.c_char_p),('comment',C.c_char_p),('reserved',C.c_void_p)]
class Menu(C.Structure):
 _fields_=[(n,C.c_int) for n in ('page_size','page_no','is_last_page','highlighted_candidate_index','num_candidates')]+[('candidates',C.POINTER(Candidate)),('select_keys',C.c_char_p)]
class Context(C.Structure):
 _fields_=[('data_size',C.c_int),('composition',Composition),('menu',Menu),('commit_text_preview',C.c_char_p),('select_labels',C.POINTER(C.c_char_p))]
class Commit(C.Structure):
 _fields_=[('data_size',C.c_int),('text',C.c_char_p)]
def bind(name,args,ret):
 f=getattr(r,name); f.argtypes=args; f.restype=ret; return f
setup=bind('_Z9RimeSetupP13rime_traits_t',[C.POINTER(Traits)],None)
init=bind('_Z14RimeInitializeP13rime_traits_t',[C.POINTER(Traits)],None)
final=bind('_Z12RimeFinalizev',[],None)
create=bind('_Z17RimeCreateSessionv',[],C.c_size_t)
select=bind('_Z16RimeSelectSchemamPKc',[C.c_size_t,C.c_char_p],C.c_int)
option=bind('_Z13RimeSetOptionmPKci',[C.c_size_t,C.c_char_p,C.c_int],None)
key=bind('_Z14RimeProcessKeymii',[C.c_size_t,C.c_int,C.c_int],C.c_int)
clear=bind('_Z20RimeClearCompositionm',[C.c_size_t],None)
getctx=bind('_Z14RimeGetContextmP14rime_context_t',[C.c_size_t,C.POINTER(Context)],C.c_int)
freectx=bind('_Z15RimeFreeContextP14rime_context_t',[C.POINTER(Context)],C.c_int)
getcommit=bind('_Z13RimeGetCommitmP13rime_commit_t',[C.c_size_t,C.POINTER(Commit)],C.c_int)
freecommit=bind('_Z14RimeFreeCommitP13rime_commit_t',[C.POINTER(Commit)],C.c_int)
modules=(C.c_char_p*4)(b'default',b'lua',b'cloud_pinyin',None)
t=Traits(); t.data_size=C.sizeof(t)-C.sizeof(C.c_int); t.shared_data_dir=str(APP/'Contents/SharedSupport').encode(); t.user_data_dir=str(ROOT).encode(); t.app_name=b'rime.wubi_smart_test'; t.modules=modules; t.min_log_level=2; t.log_dir=str(ROOT).encode()
setup(C.byref(t)); init(C.byref(t)); s=create(); assert select(s,b'wubi86'); option(s,b'ascii_mode',0)
option(s,b'cloud_pinyin',0) # Local regression checks never send network requests.
def snapshot():
 ctx=Context(); ctx.data_size=C.sizeof(ctx)-4; assert getctx(s,C.byref(ctx))
 result=((ctx.composition.preedit or b'').decode(),[(ctx.menu.candidates[i].text or b'').decode() for i in range(ctx.menu.num_candidates)])
 freectx(C.byref(ctx)); return result
def commit():
 c=Commit(); c.data_size=C.sizeof(c)-4
 if getcommit(s,C.byref(c)):
  result=(c.text or b'').decode(); freecommit(C.byref(c)); return result
 return ''
def type_text(text):
 for ch in text:
  assert key(s,ord(ch),0),ch
  assert not commit(), f'Unexpected auto commit in {text!r}'
for text in ['aaaa','niha','nihao','nihaoshijie','ren gong zhi neng'.replace(' ',''),'zznihao','zhongguo']:
 clear(s); type_text(text); print(text, snapshot())
clear(s); type_text('nihao'); assert '你好' in snapshot()[1]; key(s,0xff08,0); print('backspace',snapshot()); assert '你好' not in snapshot()[1]
clear(s); type_text('nihao'); key(s,ord(' '),0); assert commit() == '你好'
clear(s); type_text('nihaoai'); assert snapshot()[1][1] == '你好'
key(s,ord('2'),0); assert '爱' in snapshot()[1]; assert not commit()
key(s,ord(' '),0); assert commit() == '你好爱'
clear(s); type_text('nihaoshijie'); key(s,0xff51,0); key(s,0xff08,0)
assert snapshot()[0].endswith('jie'); assert not commit()
clear(s); type_text('aaaa'); assert snapshot()[1]; assert not commit()
clear(s); type_text('zznihao'); assert '你好' in snapshot()[1]; assert not commit()
clear(s); type_text('zhongguo'); assert '中国' in snapshot()[1]; assert not commit()
clear(s); type_text('zhishi'); assert '知识' in snapshot()[1]; assert not commit()
clear(s); type_text('zzni'); assert '你' in snapshot()[1]; assert not commit()
clear(s)
for ch in '/bq': key(s,ord(ch),0)
assert '😂' in snapshot()[1]; assert not commit()
clear(s); type_text('nihao'); key(s,0xff1b,0); assert not snapshot()[1]; assert not commit()
final()
print('PASS: no automatic commit, fifth-letter pinyin, backspace, partial selection, caret editing, complete z pinyin, zz lookup, punctuation, Escape')
