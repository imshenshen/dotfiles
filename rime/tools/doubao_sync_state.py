"""Read-only, bounded decoder for the verified Doubao sync-state format.

Never returns account IDs, paths, dictionary text, response bodies or credentials.
Field meanings are recovered from SyncTaskStateStore::Save and OnFinishInput in
the engine pinned by research_doubao_dictionary.py. This is diagnostics, not a
cloud client or a claim that a particular word has synced.
"""
from __future__ import annotations

import hashlib
from pathlib import Path


def _varint(data: bytes, offset: int) -> tuple[int, int]:
    value = 0
    for shift in range(0, 70, 7):
        if offset >= len(data):
            raise ValueError('Truncated sync-state varint')
        byte = data[offset]
        offset += 1
        if shift == 63 and byte > 1:
            raise ValueError('Oversized sync-state varint')
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
    raise ValueError('Oversized sync-state varint')


def _fields(data: bytes) -> dict[int, int | bytes]:
    if len(data) > 64 * 1024:
        raise ValueError('Oversized sync state')
    result: dict[int, int | bytes] = {}
    offset = 0
    while offset < len(data):
        tag, offset = _varint(data, offset)
        field, wire = tag >> 3, tag & 7
        if not 0 < field < 2**29 or field in result:
            raise ValueError('Invalid or duplicate sync-state field')
        if wire == 0:
            value, offset = _varint(data, offset)
        elif wire == 2:
            length, offset = _varint(data, offset)
            end = offset + length
            if end > len(data):
                raise ValueError('Truncated sync-state field')
            value, offset = data[offset:end], end
        else:
            raise ValueError('Unverified sync-state wire type')
        result[field] = value
    return result


def decode_state(data: bytes, side: bytes, account_directory: Path) -> dict:
    state = _fields(data)
    if state.get(1) != 1 or set(state) - {1, 2, 3, 4, 5, 6}:
        raise ValueError('Unverified sync-state schema')
    account = state.get(2)
    directory = state.get(3)
    if not isinstance(account, bytes) or not account or not isinstance(directory, bytes):
        raise ValueError('Missing sync-state identity')
    try:
        # Compare internally; never include either value in diagnostics/errors.
        directory_matches = Path(directory.decode('utf-8')).resolve() == account_directory.resolve()
    except (UnicodeDecodeError, ValueError):
        raise ValueError('Invalid sync-state directory') from None
    result: dict = {'schemaVersion': 1, 'accountDirectoryMatches': directory_matches}
    number = state.get(4, 0)
    if not isinstance(number, int):
        raise ValueError('Invalid sync-state timestamp')
    result['lastScheduleMs'] = number
    for field, label in ((5, 'upload'), (6, 'download')):
        raw = state.get(field, b'')
        if not isinstance(raw, bytes):
            raise ValueError('Invalid nested sync state')
        nested = _fields(raw)
        allowed = {1} if field == 5 else {1, 2, 3}
        if set(nested) - allowed:
            raise ValueError('Unverified nested sync-state schema')
        first = nested.get(1, 0)
        if not isinstance(first, int):
            raise ValueError('Invalid sync-state version')
        if label == 'upload':
            result['uploadedThroughMs'] = first
        else:
            size, md5 = nested.get(3, 0), nested.get(2, b'')
            if not isinstance(size, int) or not isinstance(md5, bytes):
                raise ValueError('Invalid downloaded file metadata')
            result['downloadVersionSeq'] = first
            result['downloadedBytes'] = size
            # The stored hash describes a downloaded artifact. A later native
            # rewrite may change the side file; a mismatch alone is NOT a failed
            # download or failed word sync.
            result['sideMatchesStoredDownloadMD5'] = bool(
                size == len(side) and md5.lower() == hashlib.md5(side).hexdigest().encode('ascii'))
    return result


def read_status(live_root: Path, account_directory: Path, side: bytes) -> dict:
    states = list((live_root / 'EngineSync').glob('*/sync/sync_state'))
    if len(states) != 1:
        raise ValueError('Expected exactly one sync state; ambiguous accounts are not selected')
    state = states[0]
    root = (live_root / 'EngineSync').resolve()
    if state.is_symlink() or root not in state.resolve().parents:
        raise ValueError('Unexpected sync-state path')
    with state.open('rb') as source:
        data = source.read(64 * 1024 + 1)
    if len(data) > 64 * 1024:
        raise ValueError('Oversized sync state')
    with state.open('rb') as source:
        second = source.read(64 * 1024 + 1)
    if data != second:
        raise ValueError('Sync state is changing; retry after input stops')
    return decode_state(data, side, account_directory)
