#!/usr/bin/env python3
"""Version-pinned, offline interoperability research. Never edits live dictionaries.

inspect: read a consistent private copy of the single account's side dictionary.
selftest: exercise native CRUD only in fresh synthetic dictionaries.
status: read sync versions and compare stored hashes without native code.
Requires macOS, Xcode command line tools and an installed, supported Doubao IME.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile

from doubao_sync_state import read_status

ROOT = Path(__file__).resolve().parents[1]
APP = Path('/Library/Input Methods/DoubaoIme.app')
FRAMEWORKS = APP / 'Contents/Frameworks'
ENGINE = FRAMEWORKS / 'OimeEngine.framework/Versions/A/OimeEngine'
LIVE = Path.home() / 'Library/Application Support/DoubaoIme'
# Private C++ layout and synthetic object construction are valid ONLY for this
# binary. Refuse future versions rather than infer ABI compatibility from 1.0.2.
ENGINE_SHA256 = 'f0da51a994a8a78b2955a45f14ddabc1a308bfcd4462961393c8881eb0217f62'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def policy_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def run_probe(kind: str, directory: Path, work: Path, export: bool = False) -> str:
    source = ROOT / 'native/doubao-dictionary' / f'{kind}_probe.cpp'
    binary = work / f'{kind}_probe'
    subprocess.run(['xcrun', 'clang++', '-std=c++17', '-Wall', '-Wextra',
                    str(source), '-Wl,-rpath,' + str(FRAMEWORKS), '-o', str(binary)],
                   check=True, capture_output=True, text=True, timeout=120)
    # Doubao libraries cannot read live account data, write outside this private
    # work directory, or make network requests, even during library initialization.
    policy = ('(version 1)(allow default)(deny network*)'
              f'(deny file-read* (subpath {policy_string(str(LIVE))}))'
              '(deny file-write* (require-not '
              f'(subpath {policy_string(str(work))})))')
    argv = ['/usr/bin/sandbox-exec', '-p', policy, str(binary), str(ENGINE), str(directory)]
    if export:
        argv.append(str(work / 'export.private.txt'))
    result = subprocess.run(argv, check=True, capture_output=True, text=True, timeout=30)
    return result.stdout.strip()


def account_source(account: Path | None) -> Path:
    root = (LIVE / 'EngineUserDictAccounts').resolve()
    if account:
        directory = account.expanduser().resolve()
        if directory.parent != root:
            raise ValueError('Account directory must be immediately below EngineUserDictAccounts')
        source = directory / 'usr_side_dict.dat'
    else:
        sources = list(root.glob('*/usr_side_dict.dat'))
        if len(sources) != 1:
            raise ValueError('Expected exactly one account dictionary; select --account-directory explicitly')
        source = sources[0]
    if source.is_symlink() or source.resolve().parent.parent != root:
        raise ValueError('Refusing a dictionary symlink or unexpected path')
    return source


def stable_side(source: Path) -> bytes:
    def read() -> bytes:
        with source.open('rb') as stream:
            return stream.read(64 * 1024 * 1024 + 1)

    for _ in range(3):
        data = read()
        if data == read():
            break
    else:
        raise ValueError('Dictionary is changing; retry after input has stopped')
    if len(data) < 48 or len(data) > 64 * 1024 * 1024:
        raise ValueError('Unsupported dictionary size')
    return data


def snapshot(target: Path, account: Path | None) -> dict:
    data = stable_side(account_source(account))
    destination = target / 'usr_side_dict.dat'
    destination.write_bytes(data)
    destination.chmod(0o600)
    return {'snapshotBytes': len(data), 'snapshotSHA256': hashlib.sha256(data).hexdigest()}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('operation', choices=['inspect', 'selftest', 'status'])
    parser.add_argument('--account-directory', type=Path)
    parser.add_argument('--export', type=Path, help='Explicitly export private words; refuses existing destination')
    args = parser.parse_args()
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        parser.error('This research ABI has only been verified on macOS arm64')
    if not ENGINE.is_file() or digest(ENGINE) != ENGINE_SHA256:
        parser.error('Unverified Doubao engine binary: refusing private ABI calls')
    if args.operation == 'status' and args.export:
        parser.error('Status never exports private words')
    if args.operation == 'selftest' and (args.account_directory or args.export):
        parser.error('Selftest only uses synthetic dictionaries')
    if args.operation == 'status':
        source = account_source(args.account_directory)
        side = stable_side(source)
        status = read_status(LIVE, source.parent, side)
        status['sideSnapshotSHA256'] = hashlib.sha256(side).hexdigest()
        status['wordRoundTripVerified'] = False
        print(json.dumps(status, ensure_ascii=False, indent=2))
        return
    os.umask(0o077)
    runs = ROOT / '.build/doubao-dictionary-research/runs'
    runs.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix='probe-', dir=runs) as name:
        work = Path(name).resolve()
        if args.operation == 'inspect':
            copied = work / 'snapshot'
            copied.mkdir(mode=0o700)
            metadata = snapshot(copied, args.account_directory)
            print(json.dumps(metadata))
            print(run_probe('side', copied, work, bool(args.export)))
            local = account_source(args.account_directory).parent / 'usr.dat'
            if local.is_file():
                if local.is_symlink():
                    raise ValueError('Refusing a learned dictionary symlink')
                (copied / 'usr.dat').write_bytes(stable_side(local))
                print(run_probe('learned_snapshot', copied, work))
            if args.export:
                # Only the explicitly requested export survives this temporary run.
                destination = args.export.expanduser().absolute()
                fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, 'wb') as out:
                    out.write((work / 'export.private.txt').read_bytes())
                print('Private export saved with mode 0600; do not add it to Git.')
        else:
            for kind in ['common_phrase', 'learned']:
                copied = work / kind
                copied.mkdir(mode=0o700)
                print(run_probe(kind, copied, work))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        # Never echo subprocess argv, account paths, or an unfiltered native log.
        print(f'Research probe failed ({type(error).__name__}). Live dictionary was not written.')
        raise SystemExit(1)
