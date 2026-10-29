import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    'doubao_sync_state', Path(__file__).resolve().parents[1] / 'tools' / 'doubao_sync_state.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    return bytes(out) + bytes([value])


def field(number, value):
    if isinstance(value, int):
        return varint(number << 3) + varint(value)
    return varint((number << 3) | 2) + varint(len(value)) + value


class SyncStateTests(unittest.TestCase):
    def setUp(self):
        self.directory = Path('/tmp/synthetic-doubao-account')
        self.side = b'synthetic-side-snapshot'
        self.state = b''.join([
            field(1, 1), field(2, b'PRIVATE-ACCOUNT-SENTINEL'),
            field(3, str(self.directory).encode()), field(4, 1792426140000),
            field(5, field(1, 1792426139000)),
            field(6, field(1, 42) + field(2, hashlib.md5(self.side).hexdigest().encode())
                  + field(3, len(self.side)))])

    def test_metadata_only(self):
        result = module.decode_state(self.state, self.side, self.directory)
        self.assertTrue(result['accountDirectoryMatches'])
        self.assertTrue(result['sideMatchesStoredDownloadMD5'])
        self.assertEqual(result['downloadVersionSeq'], 42)
        self.assertEqual(result['uploadedThroughMs'], 1792426139000)
        self.assertNotIn('PRIVATE-ACCOUNT-SENTINEL', repr(result))
        self.assertNotIn(str(self.directory), repr(result))

    def test_different_side_hash_is_observation_not_exception(self):
        result = module.decode_state(self.state, b'different', self.directory)
        self.assertFalse(result['sideMatchesStoredDownloadMD5'])

    def test_account_path_mismatch(self):
        self.assertFalse(module.decode_state(
            self.state, self.side, Path('/tmp/another-account'))['accountDirectoryMatches'])

    def test_unknown_schema_and_corrupt_data_fail_closed(self):
        cases = [b'', b'\x80', b'\x08' + b'\xff' * 10 + b'\x01',
                 b'\x1a\x04ab', self.state + field(1, 1),
                 self.state + field(7, 7), b'x' * 65537,
                 field(1, 2) + field(2, b'account') + field(3, b'/tmp')]
        for data in cases:
            with self.subTest(length=len(data)), self.assertRaises(ValueError) as failure:
                module.decode_state(data, self.side, self.directory)
            self.assertNotIn('PRIVATE-ACCOUNT-SENTINEL', str(failure.exception))


if __name__ == '__main__':
    unittest.main()
