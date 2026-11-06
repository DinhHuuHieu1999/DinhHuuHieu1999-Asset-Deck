"""Import orchestration contracts: no real process, socket or TLS access."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import MagicMock, patch
from types import SimpleNamespace

spec = importlib.util.spec_from_file_location('import_v4_fixture', Path(__file__).with_name('import-v4-https-fixture.py'))
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)
real_negative_acceptance = fixture.negative_acceptance
real_write_checkpoint = fixture.write_checkpoint


class ImportV4FixtureTests(unittest.TestCase):
    def setUp(self):
        checkpoints = patch.object(fixture, 'write_checkpoint')
        checkpoints.start()
        self.addCleanup(checkpoints.stop)
        negative = patch.object(fixture, 'negative_acceptance', return_value={'offlineMock': True})
        negative.start()
        self.addCleanup(negative.stop)
        for module, name in [(fixture.client.subprocess, 'run'),
                             (fixture.client.subprocess, 'Popen'),
                             (fixture.client.socket, 'socket')]:
            guard = patch.object(module, name, side_effect=AssertionError('Forbidden IO'))
            guard.start()
            self.addCleanup(guard.stop)

    def test_disabled_profile_never_invokes_dart_import(self):
        runtime = MagicMock()
        expected = {'disabledRoute404': True, 'unchangedCounts': True}
        with patch.object(fixture, 'negative_acceptance', return_value=expected) as negative:
            result = fixture.acceptance(Path('/synthetic'),
                SimpleNamespace(disabled_v4_route=True), runtime, Path('/private'), 'a'*32, None, None)
        self.assertEqual(result, dict(status='completed', syntheticOnly=True, **expected))
        self.assertTrue(negative.call_args.kwargs['disabled'])
        runtime.run.assert_not_called()

    def test_exact_result_invokes_driver_once_with_marker(self):
        runtime = MagicMock()
        runtime.run.return_value = json.dumps(fixture.EXPECTED).encode()
        root = Path('/synthetic')
        args = SimpleNamespace(dart='synthetic-dart', tls_port=19003)
        result = fixture.acceptance(root, args, runtime, None, 'a'*32, None, None)
        self.assertEqual(result, dict(fixture.EXPECTED, rejectionAcceptance={'offlineMock': True}))
        runtime.run.assert_called_once()
        command = runtime.run.call_args.args[0]
        self.assertIn('--disable-dart-dev', command)
        self.assertIn('a'*32, command)
        self.assertIn('https://localhost:19003/api/v1', command)

    def test_partial_wrong_or_ambiguous_result_refused_without_retry(self):
        for value in [{}, [], dict(fixture.EXPECTED, owners=True),
                      dict(fixture.EXPECTED, imported=3),
                      dict(fixture.EXPECTED, extra=True)]:
            runtime = MagicMock()
            runtime.run.return_value = json.dumps(value).encode()
            with self.assertRaises(fixture.client.Refusal):
                fixture.acceptance(Path('/synthetic'), SimpleNamespace(dart='dart', tls_port=19003),
                                   runtime, None, 'a'*32, None, None)
            runtime.run.assert_called_once()

    def test_missing_driver_source_refuses_before_lifecycle(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in fixture.DRIVER_FILES:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('synthetic', encoding='utf-8')
            for name in fixture.DRIVER_FILES:
                p = root / name
                p.unlink()
                with patch.object(fixture.client, 'preflight') as base:
                    with self.assertRaises(fixture.client.Refusal):
                        fixture.preflight(root, SimpleNamespace(import_v4_mode=True))
                    base.assert_not_called()
                p.write_text('synthetic', encoding='utf-8')

    def test_default_profile_refuses_without_resources(self):
        with self.assertRaises(fixture.client.Refusal):
            fixture.preflight(Path('/synthetic'), SimpleNamespace())

    def test_preflight_delegates_only_after_fixed_sources_exist(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in fixture.DRIVER_FILES:
                p = root / name
                p.parent.mkdir(parents=True, exist_ok=True)
                p.write_text('synthetic', encoding='utf-8')
            args = SimpleNamespace(import_v4_mode=True)
            with patch.object(fixture.client, 'preflight') as base:
                fixture.preflight(root, args)
                base.assert_called_once_with(root, args)

    def test_rejections_are_exact_and_counts_unchanged(self):
        request = MagicMock()
        counts = MagicMock(side_effect=[b'0|0', b'0|0'])
        result = fixture.rejection_cases(request, counts)
        self.assertTrue(result['unchangedCounts'])
        self.assertEqual(request.call_count, 13)
        self.assertEqual([c.kwargs['expected'] for c in request.call_args_list],
                         [401, 403, 400, 400, 400, 400, 400, 400, 400, 400, 400, 400, 413])
        self.assertFalse(request.call_args_list[0].kwargs['authenticated'])
        self.assertFalse(request.call_args_list[1].kwargs['csrf'])
        self.assertEqual(len(request.call_args_list[-1].args[0]), 1024*1024+1)
        self.assertEqual(counts.call_count, 2)
        self.assertEqual(request.call_args_list[5].args[0]['records'][0]['purchasedOn'], '2023-02-29')
        self.assertNotIn('warrantyExpiresOn', request.call_args_list[6].args[0]['records'][0])
        self.assertIsInstance(request.call_args_list[7].args[0], bytes)
        self.assertEqual(request.call_args_list[7].args[0].count(b'"records"'), 2)

    def test_rejection_mutation_fails_closed(self):
        with self.assertRaises(fixture.client.Refusal):
            fixture.rejection_cases(MagicMock(), MagicMock(side_effect=[b'0|0', b'1|1']))

    def test_rejection_failure_does_not_retry(self):
        request = MagicMock(side_effect=fixture.client.Refusal('Synthetic failure'))
        with self.assertRaises(fixture.client.Refusal):
            fixture.rejection_cases(request, MagicMock(return_value=b'0|0'))
        request.assert_called_once()

    def test_negative_transport_marker_auth_csrf_and_fixed_statuses(self):
        identity = 'a'*32
        outputs = [(200, {'fixtureId': identity, 'syntheticOnly': True}),
                   (200, {'token': 'synthetic-csrf'}),
                   (201, {'accessToken': 'synthetic-token'})]
        outputs += [(status, {'error': 'synthetic'}) for status in [401, 403, 400, 400, 400, 400, 400, 400, 400, 400, 400, 400, 413]]
        class Response:
            def __init__(self, value): self.status, self.value = value
            def read(self, limit): return json.dumps(self.value).encode()
            def __enter__(self): return self
            def __exit__(self, *args): pass
        opener = MagicMock()
        opener.open.side_effect = [Response(value) for value in outputs]
        runtime = MagicMock()
        runtime.remaining.return_value = 10
        runtime.run.return_value = b'0|0'
        with patch.object(fixture.urllib.request, 'build_opener', return_value=opener), \
             patch.object(fixture.client, 'assert_owned') as owned:
            result = real_negative_acceptance(SimpleNamespace(tls_port=19003), runtime, identity)
        self.assertTrue(result['unchangedCounts'])
        owned.assert_called_once_with(runtime, 'asset-client-'+identity, identity)
        requests = [call.args[0] for call in opener.open.call_args_list]
        self.assertEqual(len(requests), 16)
        self.assertTrue(requests[0].full_url.endswith('/__asset_desk_fixture/'+identity))
        self.assertIsNone(requests[3].get_header('Authorization'))
        self.assertEqual(requests[3].get_header('X-csrf-token'), 'synthetic-csrf')
        self.assertEqual(requests[4].get_header('Authorization'), 'Bearer synthetic-token')
        self.assertIsNone(requests[4].get_header('X-csrf-token'))
        self.assertEqual(runtime.run.call_count, 2)

    def test_disabled_http_404_uses_auth_csrf_and_preserves_counts(self):
        identity = 'a'*32
        outputs = [(200, {'fixtureId': identity, 'syntheticOnly': True}),
                   (200, {'token': 'synthetic-csrf'}),
                   (201, {'accessToken': 'synthetic-token'}),
                   (404, {'error': 'not found'})]
        class Response:
            def __init__(self, value): self.status, self.value = value
            def read(self, limit): return json.dumps(self.value).encode()
            def __enter__(self): return self
            def __exit__(self, *args): pass
        opener = MagicMock()
        opener.open.side_effect = [Response(value) for value in outputs]
        runtime = MagicMock()
        runtime.remaining.return_value = 10
        runtime.run.return_value = b'0|0'
        with patch.object(fixture.urllib.request, 'build_opener', return_value=opener), \
             patch.object(fixture.client, 'assert_owned'):
            result = real_negative_acceptance(SimpleNamespace(tls_port=19003), runtime, identity, disabled=True)
        self.assertEqual(result, {'disabledRoute404': True, 'unchangedCounts': True})
        request = opener.open.call_args.args[0]
        self.assertTrue(request.full_url.endswith('/api/v1/assets/import/v4'))
        self.assertEqual(request.get_header('Authorization'), 'Bearer synthetic-token')
        self.assertEqual(request.get_header('X-csrf-token'), 'synthetic-csrf')
        self.assertEqual(runtime.run.call_count, 2)

    def test_wrong_marker_prevents_registration_and_database_access(self):
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 200
        response.read.return_value = b'{"fixtureId":"wrong","syntheticOnly":true}'
        opener = MagicMock()
        opener.open.return_value = response
        runtime = MagicMock()
        runtime.remaining.return_value = 10
        with patch.object(fixture.urllib.request, 'build_opener', return_value=opener):
            with self.assertRaises(fixture.client.Refusal):
                real_negative_acceptance(SimpleNamespace(tls_port=19003), runtime, 'a'*32)
        opener.open.assert_called_once()
        runtime.run.assert_not_called()

    def test_checkpoint_refuses_private_or_unbounded_fields(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            for details in [{'stage': 'token'}, {'stage': 'negative-http', 'token': 'private'},
                {'stage': 'negative-http', 'observedStatus': True},
                {'stage': 'negative-http', 'requestIndex': 'private'},
                {'stage': 'negative-transport', 'certificateVerification': 'private'}]:
                with self.assertRaises(fixture.client.Refusal):
                    real_write_checkpoint(folder, details)
                self.assertEqual(list(folder.iterdir()), [])
            details = {'stage': 'negative-response', 'requestIndex': 3,
                       'expectedStatus': 201, 'observedStatus': 403}
            real_write_checkpoint(folder, details)
            self.assertEqual(json.loads((folder/'import-checkpoint.json').read_text()), details)

    def test_tls_failure_records_only_fixed_safe_diagnostics(self):
        opener = MagicMock()
        opener.open.side_effect = fixture.urllib.error.URLError(
            fixture.ssl.SSLCertVerificationError('private error text'))
        runtime = MagicMock()
        runtime.remaining.return_value = 10
        checkpoint = MagicMock()
        with patch.object(fixture.urllib.request, 'build_opener', return_value=opener):
            with self.assertRaises(fixture.client.Refusal) as caught:
                real_negative_acceptance(SimpleNamespace(tls_port=19003), runtime, 'a'*32, checkpoint)
        self.assertNotIn('private', str(caught.exception))
        self.assertEqual(checkpoint.call_args.kwargs,
                         {'stage': 'negative-transport', 'requestIndex': 1,
                          'certificateVerification': True})
        opener.open.assert_called_once()
        runtime.run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
