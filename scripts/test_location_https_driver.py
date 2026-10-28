"""Offline warranty HTTPS orchestration; no network or real process invocation."""
import importlib.util
import hashlib
import json
import sys
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('location_tls_driver_test', Path(__file__).with_name('location-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class LocationDriverTests(unittest.TestCase):
    def test_missing_each_source_refuses_before_shared_preflight(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.FILES:
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            for name in m.FILES:
                target = root/name
                target.unlink()
                with patch.object(m.client, 'preflight') as shared:
                    with self.assertRaises(m.client.Refusal): m.preflight(root, SimpleNamespace())
                    shared.assert_not_called()
                target.write_text('synthetic', encoding='utf-8')

    @staticmethod
    def result():
        return dict(status='completed', syntheticOnly=True, locationAcceptance=True, locationOverviewAcceptance=True, assetDetailsAcceptance=True, owners=2, assetCount=53, digest='python-sha256-stdin', nativeDialog='not-exercised')

    def test_exact_typed_output_required(self):
        m.validate_result(self.result())
        for value in ({}, [], None, dict(self.result(), owners=True),
                      dict(self.result(), assetCount=1), dict(self.result(), syntheticOnly=1),
                      dict(self.result(), locationOverviewAcceptance=1), dict(self.result(), locationOverviewAcceptance=False), dict(self.result(), locationAcceptance=1), dict(self.result(), extra=True)):
            with self.assertRaises(m.client.Refusal): m.validate_result(value)

    def test_old_success_without_overview_is_rejected(self):
        old = self.result()
        del old['locationOverviewAcceptance']
        with self.assertRaises(m.client.Refusal):
            m.validate_result(old)

    def test_old_success_without_details_is_rejected(self):
        old = self.result()
        del old['assetDetailsAcceptance']
        with self.assertRaises(m.client.Refusal):
            m.validate_result(old)

    def test_driver_runs_once_with_fixed_source_and_endpoint(self):
        calls = []
        class Runtime:
            def run(self, command, **kwargs):
                calls.append((command, kwargs))
                return json.dumps(LocationDriverTests.result()).encode()
        with patch.object(m, 'source_hashes', return_value={'fixed': 'digest'}):
            result = m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)
        self.assertEqual(result['locationSourceHashes'], {'fixed': 'digest'})
        self.assertTrue(result['locationDartClient'])
        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0][0], ['sdk.exe', '--disable-dart-dev', str(Path('source')/m.FILES[0]),
            '--synthetic-only', 'https://localhost:59233/api/v1', 'a'*32, sys.executable])

    def test_safe_stage_failure_is_saved_but_never_passes(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{"status":"failed","stage":"pagination","secret":"not-retained"}'
        with tempfile.TemporaryDirectory() as folder:
            with patch.object(m, 'source_hashes', return_value={}), self.assertRaises(m.client.Refusal):
                m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), Path(folder), 'a'*32, None, None)
            self.assertEqual(json.loads((Path(folder)/'location-diagnostic.json').read_text()), {'status':'failed','stage':'pagination'})

    def test_incomplete_output_never_returns_success(self):
        class Runtime:
            def run(self, *args, **kwargs): return b'{}'
        with patch.object(m, 'source_hashes', return_value={}), self.assertRaises(m.client.Refusal):
            m.acceptance(Path('.'), SimpleNamespace(dart='sdk.exe', tls_port=59233), Runtime(), None, 'a'*32, None, None)


    def test_source_hashes_are_exact_and_ignore_unlisted_private_files(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in m.FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'public synthetic bytes')
            private = root/'private.env'
            private.write_bytes(b'private-not-selected')
            expected = {name: hashlib.sha256(b'public synthetic bytes').hexdigest() for name in m.FILES}
            original = Path.read_bytes
            def guarded(path):
                self.assertNotEqual(path, private)
                return original(path)
            with patch.object(Path, 'read_bytes', guarded):
                self.assertEqual(m.source_hashes(root), expected)

    def test_source_drift_or_missing_artifact_never_returns_success(self):
        for changed in ({'fixed': 'changed'}, OSError('missing')):
            with self.subTest(changed=type(changed).__name__):
                runtime = unittest.mock.Mock()
                runtime.run.return_value = json.dumps(self.result()).encode()
                with patch.object(m, 'source_hashes', side_effect=[{'fixed': 'before'}, changed]):
                    with self.assertRaises((m.client.Refusal, OSError)):
                        m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=59233), runtime, None, 'a'*32, None, None)
                runtime.run.assert_called_once()

    def test_missing_hash_source_prevents_driver_execution(self):
        runtime = unittest.mock.Mock()
        with patch.object(m, 'source_hashes', side_effect=OSError('missing')):
            with self.assertRaises(OSError):
                m.acceptance(Path('source'), SimpleNamespace(dart='sdk.exe', tls_port=59233), runtime, None, 'a'*32, None, None)
        runtime.run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
