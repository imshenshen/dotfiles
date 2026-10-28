"""Actual installed/backend Rime calls, restricted to an isolated temporary user directory."""
import ctypes as C
import tempfile
from pathlib import Path


class Traits(C.Structure):
    _fields_ = [('data_size', C.c_int)] + [(name, C.c_char_p) for name in (
        'shared_data_dir', 'user_data_dir', 'distribution_name', 'distribution_code_name',
        'distribution_version', 'app_name')] + [('modules', C.POINTER(C.c_char_p)),
        ('min_log_level', C.c_int)] + [(name, C.c_char_p) for name in (
        'log_dir', 'prebuilt_data_dir', 'staging_dir')]


class Composition(C.Structure):
    _fields_ = [(name, C.c_int) for name in ('length', 'cursor_pos', 'sel_start', 'sel_end')] + [('preedit', C.c_char_p)]


class Candidate(C.Structure):
    _fields_ = [('text', C.c_char_p), ('comment', C.c_char_p), ('reserved', C.c_void_p)]


class Menu(C.Structure):
    _fields_ = [(name, C.c_int) for name in ('page_size', 'page_no', 'is_last_page',
        'highlighted_candidate_index', 'num_candidates')] + [('candidates', C.POINTER(Candidate)), ('select_keys', C.c_char_p)]


class Context(C.Structure):
    _fields_ = [('data_size', C.c_int), ('composition', Composition), ('menu', Menu),
                ('commit_text_preview', C.c_char_p), ('select_labels', C.POINTER(C.c_char_p))]


class Commit(C.Structure):
    _fields_ = [('data_size', C.c_int), ('text', C.c_char_p)]


class Rime:
    def __init__(self, root, app, plugin=None, shared=None, log_level=2):
        self.root, self.app = Path(root).resolve(), Path(app).resolve()
        self.shared = Path(shared).resolve() if shared else self.app / 'Contents/SharedSupport'
        assert self.root.is_relative_to(Path(tempfile.gettempdir()).resolve()) or self.root.is_relative_to(Path('/tmp').resolve())
        assert (self.root / 'build/wubi86.schema.yaml').exists() or (self.shared / 'build/wubi86.schema.yaml').exists()
        framework = self.app / 'Contents/Frameworks'
        self.lib = C.CDLL(str(framework / 'librime.1.dylib'), mode=C.RTLD_GLOBAL)
        self.lua = C.CDLL(str(framework / 'rime-plugins/librime-lua.dylib'), mode=C.RTLD_GLOBAL)
        self.cloud = C.CDLL(str(Path(plugin).resolve() if plugin else framework / 'rime-plugins/librime-cloud-pinyin.dylib'), mode=C.RTLD_GLOBAL)
        def bind(name, args, result):
            function = getattr(self.lib, name)
            function.argtypes, function.restype = args, result
            return function
        self.setup = bind('_Z9RimeSetupP13rime_traits_t', [C.POINTER(Traits)], None)
        self.initialize = bind('_Z14RimeInitializeP13rime_traits_t', [C.POINTER(Traits)], None)
        self.finalize = bind('_Z12RimeFinalizev', [], None)
        self.create = bind('_Z17RimeCreateSessionv', [], C.c_size_t)
        self.destroy = bind('_Z18RimeDestroySessionm', [C.c_size_t], C.c_int)
        self.select = bind('_Z16RimeSelectSchemamPKc', [C.c_size_t, C.c_char_p], C.c_int)
        self.option = bind('_Z13RimeSetOptionmPKci', [C.c_size_t, C.c_char_p, C.c_int], None)
        self.key = bind('_Z14RimeProcessKeymii', [C.c_size_t, C.c_int, C.c_int], C.c_int)
        self.clear = bind('_Z20RimeClearCompositionm', [C.c_size_t], None)
        self.getctx = bind('_Z14RimeGetContextmP14rime_context_t', [C.c_size_t, C.POINTER(Context)], C.c_int)
        self.freectx = bind('_Z15RimeFreeContextP14rime_context_t', [C.POINTER(Context)], C.c_int)
        self.getcommit = bind('_Z13RimeGetCommitmP13rime_commit_t', [C.c_size_t, C.POINTER(Commit)], C.c_int)
        self.freecommit = bind('_Z14RimeFreeCommitP13rime_commit_t', [C.POINTER(Commit)], C.c_int)
        self.notify_type = C.CFUNCTYPE(None, C.c_void_p, C.c_size_t, C.c_char_p, C.c_char_p)
        self.set_notify = bind('_Z26RimeSetNotificationHandlerPFvPvmPKcS1_ES_', [self.notify_type, C.c_void_p], None)
        self.notifications = []
        self.notify = self.notify_type(lambda _, session, kind, value: self.notifications.append((session, kind, value)))
        self.set_notify(self.notify, None)
        self.modules = (C.c_char_p * 4)(b'default', b'lua', b'cloud_pinyin', None)
        self.traits = Traits()
        self.traits.data_size = C.sizeof(Traits) - C.sizeof(C.c_int)
        self.traits.shared_data_dir = str(self.shared).encode()
        self.traits.user_data_dir = str(self.root).encode()
        self.traits.app_name = b'rime.cloud_test'
        self.traits.modules = self.modules
        self.traits.min_log_level = log_level
        self.traits.log_dir = str(self.root).encode()
        self.setup(C.byref(self.traits))
        self.initialize(C.byref(self.traits))

    def session(self, cloud=True, schema='wubi86'):
        session = self.create()
        assert self.select(session, schema.encode())
        self.option(session, b'ascii_mode', 0)
        self.option(session, b'cloud_pinyin', int(cloud))
        return session

    def snapshot(self, session):
        context = Context()
        context.data_size = C.sizeof(Context) - 4
        assert self.getctx(session, C.byref(context))
        result = dict(preedit=(context.composition.preedit or b'').decode(),
                      candidates=[((context.menu.candidates[i].text or b'').decode(),
                                   (context.menu.candidates[i].comment or b'').decode())
                                  for i in range(context.menu.num_candidates)],
                      highlight=context.menu.highlighted_candidate_index,
                      page_no=context.menu.page_no,
                      page_size=context.menu.page_size,
                      last_page=bool(context.menu.is_last_page),
                      num_candidates=context.menu.num_candidates)
        self.freectx(C.byref(context))
        return result

    def commit(self, session):
        commit = Commit()
        commit.data_size = C.sizeof(Commit) - 4
        if not self.getcommit(session, C.byref(commit)):
            return ''
        text = (commit.text or b'').decode()
        self.freecommit(C.byref(commit))
        return text

    def type(self, session, text):
        for character in text:
            assert self.key(session, ord(character), 0), character
            assert not self.commit(session), 'Unexpected automatic commit'


cf = C.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
cf.CFRunLoopRunInMode.argtypes = [C.c_void_p, C.c_double, C.c_bool]
cf.CFRunLoopRunInMode.restype = C.c_int
mode = C.c_void_p.in_dll(cf, 'kCFRunLoopDefaultMode')


def pump(seconds):
    import time
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        cf.CFRunLoopRunInMode(mode, min(.01, deadline - time.monotonic()), False)
