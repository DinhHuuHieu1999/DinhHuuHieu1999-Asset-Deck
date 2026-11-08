"""Offline export verifier contracts; never start a fixture on import."""
import hashlib
import importlib.util
import json
from pathlib import Path
import unittest
import tempfile
import time
import subprocess
import ssl
import urllib.error
from types import SimpleNamespace
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location('export_fixture', Path(__file__).with_name('export-https-fixture.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


class ExportFixtureTests(unittest.TestCase):
    def envelope(self):
        payload = json.dumps({'exportedAt': '2026-10-25T00:00:00Z', 'complete': True, 'recordCount': 0, 'records': []})
        return {'format': 'asset-desk-inventory', 'schemaVersion': 1, 'payload': payload,
                'sha256': hashlib.sha256(payload.encode()).hexdigest()}

    def test_complete_empty_snapshot(self):
        self.assertEqual(fixture.decode_export(self.envelope(), 0)['records'], [])

    def test_bad_checksum_and_count_fail_closed(self):
        for change in ({'sha256': 'a'*64}, {'schemaVersion': True}, {'format': 'other'}):
            envelope = self.envelope(); envelope.update(change)
            with self.assertRaises(fixture.client.Refusal): fixture.decode_export(envelope, 0)
        with self.assertRaises(fixture.client.Refusal): fixture.decode_export(self.envelope(), 1)

    def test_no_opt_in_refuses_before_resources(self):
        with patch('sys.argv', ['fixture']), patch.object(fixture.client, 'execute') as execute:
            self.assertEqual(fixture.main(), 1)
            execute.assert_not_called()

    def test_transport_checkpoint_has_no_private_error_details(self):
        runtime = MagicMock()
        runtime.remaining.return_value = 15
        opener = MagicMock()
        opener.open.side_effect = urllib.error.URLError(
            ssl.SSLCertVerificationError('synthetic PRIVATE DETAILS'))
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            with patch.object(fixture.urllib.request, 'build_opener', return_value=opener):
                with self.assertRaises(fixture.client.Refusal):
                    fixture.acceptance(None, SimpleNamespace(tls_port=39403), runtime,
                                       folder, 'a'*32, None, None)
            raw = (folder/'export-checkpoint.json').read_text()
            value = json.loads(raw)
            self.assertEqual(value['stage'], 'marker')
            self.assertTrue(value['certificateVerification'])
            self.assertNotIn('PRIVATE', raw)
            runtime.run.assert_not_called()
            self.assertEqual(opener.open.call_count, 1)

    def test_concurrent_snapshot_requires_observed_writer_and_exact_before_after(self):
        runtime = MagicMock(deadline=time.monotonic()+30)
        runtime.remaining.return_value = 20
        runtime.start.return_value.wait.return_value = 0
        fetch = MagicMock(side_effect=[{'records': [{'name': 'Synthetic export 1'}]},
                                       {'records': [{'name': 'Synthetic concurrent after'}]}])
        sql = MagicMock(return_value='1')
        fixture.concurrent_snapshot(runtime, Path('.'), 'owned', 'a'*32, sql, fetch)
        self.assertEqual(runtime.start.call_count, 1)
        self.assertEqual(fetch.call_count, 2)
        self.assertEqual(sql.call_count, 2)
        self.assertIn('BEGIN; UPDATE', runtime.start.call_args[0][0][-1])

    def test_concurrent_snapshot_refuses_missing_or_finished_writer(self):
        runtime = MagicMock(deadline=time.monotonic()+30)
        runtime.start.return_value.poll.return_value = 1
        fetch = MagicMock()
        with self.assertRaises(fixture.client.Refusal):
            fixture.concurrent_snapshot(runtime, Path('.'), 'owned', 'a'*32,
                                        MagicMock(return_value='0'), fetch)
        fetch.assert_not_called()
        self.assertEqual(runtime.start.call_count, 1)

    def test_concurrent_snapshot_refuses_mixed_rows_without_retry(self):
        runtime = MagicMock(deadline=time.monotonic()+30)
        fetch = MagicMock(return_value={'records': [{'name': 'Synthetic concurrent after'}]})
        with self.assertRaises(fixture.client.Refusal):
            fixture.concurrent_snapshot(runtime, Path('.'), 'owned', 'a'*32,
                                        MagicMock(return_value='1'), fetch)
        self.assertEqual(fetch.call_count, 1)
        runtime.start.return_value.wait.assert_not_called()

    def test_concurrent_snapshot_writer_timeout_is_safe_refusal(self):
        runtime = MagicMock(deadline=time.monotonic()+30)
        runtime.remaining.return_value = 20
        runtime.start.return_value.wait.side_effect = subprocess.TimeoutExpired('synthetic', 15)
        fetch = MagicMock(return_value={'records': [{'name': 'Synthetic export 1'}]})
        with self.assertRaises(fixture.client.Refusal):
            fixture.concurrent_snapshot(runtime, Path('.'), 'owned', 'a'*32,
                                        MagicMock(return_value='1'), fetch)
        self.assertEqual(runtime.start.call_count, 1)
        self.assertEqual(fetch.call_count, 1)

    def test_dart_result_is_exact_and_invoked_once(self):
        result = {'status': 'completed', 'syntheticOnly': True, 'owners': 2,
                  'assetCount': 51, 'digest': 'python-sha256-stdin',
                  'nativeDialog': 'not-exercised'}
        runtime = MagicMock()
        args = SimpleNamespace(dart='dart.exe', tls_port=39403)
        for value in (result, dict(result, assetCount=50), dict(result, extra=True), {}):
            runtime.reset_mock()
            runtime.run.return_value = json.dumps(value).encode()
            if value == result:
                fixture.run_dart_export(Path('.'), args, runtime, 'a'*32)
            else:
                with self.assertRaises(fixture.client.Refusal):
                    fixture.run_dart_export(Path('.'), args, runtime, 'a'*32)
            self.assertEqual(runtime.run.call_count, 1)

    def test_dart_preflight_missing_source_refuses_without_execute(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(fixture.client, 'preflight'), patch.object(fixture.client, 'execute') as execute:
                with self.assertRaises(fixture.client.Refusal):
                    fixture.export_preflight(Path(directory), SimpleNamespace(dart_export_client=True))
                execute.assert_not_called()

    def test_redirect_does_not_repeat_private_request(self):
        self.assertIsNone(fixture.NoRedirect().redirect_request(None, None, 302, '', {}, 'https://example.invalid'))


if __name__ == '__main__': unittest.main()
