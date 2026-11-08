"""Offline only: mocked subprocess boundary, no Docker/TLS/network."""
import importlib.util
import json
import hashlib
import subprocess
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('recovery_v2_fixture_test_target', Path(__file__).with_name('recovery-v2-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class RecoveryTests(unittest.TestCase):
    def test_missing_prerequisites_never_reach_lifecycle(self):
        with tempfile.TemporaryDirectory() as name:
            root = Path(name)
            for missing in m.FILES:
                for item in m.FILES:
                    p = root / item
                    p.parent.mkdir(parents=True, exist_ok=True)
                    p.write_text('synthetic', encoding='utf-8')
                (root / missing).unlink()
                with patch.object(m.base, 'preflight') as delegate:
                    with self.assertRaises(m.client.Refusal):
                        m.preflight(root, SimpleNamespace())
                    delegate.assert_not_called()

    def test_stage_invocations_are_exact_and_never_retry(self):
        calls = []
        class Runtime:
            def run(self, command, **kwargs):
                calls.append(command)
                return json.dumps(m.EXPECTED[command[-2]]).encode()
        for stage in m.EXPECTED:
            m.stage(Path('/synthetic'), SimpleNamespace(dart='dart', tls_port=19003), Runtime(), Path('/private'), 'a'*32, stage)
        self.assertEqual(len(calls), 3)
        self.assertEqual([c[-2] for c in calls], ['prepare', 'submit', 'replay'])
        self.assertTrue(all(c[-1] == str(Path('/private')) for c in calls))

    def test_malformed_stage_result_is_not_success(self):
        for value in [{}, {'stage': 'prepare', 'saved': 1}, dict(m.EXPECTED['prepare'], token='forbidden')]:
            runtime = SimpleNamespace(run=lambda *a, **k: json.dumps(value).encode())
            with self.assertRaises(m.client.Refusal):
                m.stage(Path('/synthetic'), SimpleNamespace(dart='dart', tls_port=19003), runtime, Path('/private'), 'a'*32, 'prepare')


class AcceptanceTests(unittest.TestCase):
    def exercise(self, mode):
        identity = 'a'*32
        key = '12345678-1234-4234-8234-123456789abc'
        calls = []
        class Proxy:
            def poll(self): return None
            def terminate(self): calls.append('terminate')
            def wait(self, timeout):
                calls.append('wait')
                if mode == 'timeout': raise subprocess.TimeoutExpired('synthetic', timeout)
        class Runtime:
            snapshots = 0
            def remaining(self): return 100
            def start(self, command, folder):
                calls.append('start')
                self.command = command
                return Proxy()
            def wait_port(self, port, child): calls.append('ready')
            def run(self, command, **kwargs):
                if 'count(*)' in command[-1]: return b'2|1'
                self.snapshots += 1
                return b'changed' if mode == 'changed' and self.snapshots > 1 else b'synthetic-rows'
        class Response:
            def __enter__(self): return self
            def __exit__(self, *args): pass
            def read(self, limit):
                return json.dumps({'fixtureId': identity, 'syntheticOnly': True,
                    'recoveryFault': {'claimed': True, 'suppressed': mode != 'marker'}}).encode()
        def stage(root, args, runtime, folder, marker, name):
            calls.append(name)
            return m.EXPECTED[name]
        with tempfile.TemporaryDirectory() as name:
            folder = Path(name)
            (folder/'recovery-control.json').write_text(json.dumps({'fixtureId':identity,
                'endpoint':'https://localhost:19003/api/v1', 'requestId':key, 'accountId':'a'*24}), encoding='utf-8')
            payload = json.dumps({'apiBase':'https://localhost:19003/api/v1/different' if mode == 'endpoint' else 'https://localhost:19003/api/v1',
                'accountId':'b'*24 if mode == 'account' else 'a'*24, 'operation':'inventory-add-only' if mode == 'operation' else 'inventory-add-only-v2',
                'requestJson':json.dumps({'requestId':'22345678-1234-4234-8234-123456789abc' if mode == 'key' else key, 'records':[]})})
            (folder/'private-import-recovery.json').write_text(json.dumps({'format':'asset-desk-import-recovery', 'schemaVersion':1 if mode == 'v1' else 2, 'payload':payload,
                'sha256':hashlib.sha256(payload.encode()).hexdigest()}), encoding='utf-8')
            args = SimpleNamespace(backend_port=19002, tls_port=19003, cert='synthetic', key='synthetic')
            with patch.object(m, 'stage', side_effect=stage), patch.object(m.client, 'assert_owned') as owned, patch.object(m.urllib.request, 'build_opener', return_value=SimpleNamespace(open=lambda *a, **k: Response())):
                runtime = Runtime()
                if mode == 'success':
                    result = m.acceptance(Path('/source'), args, runtime, folder, identity, object(), Proxy())
                    self.assertTrue(result['unchangedRows'])
                    self.assertEqual(calls, ['prepare','terminate','wait','start','ready','submit','replay'])
                    self.assertEqual(runtime.command[-2:], ['--lose-import-ack',key])
                    owned.assert_called_once()
                else:
                    with self.assertRaises(m.client.Refusal):
                        m.acceptance(Path('/source'), args, runtime, folder, identity, object(), Proxy())
                    if mode in ('timeout','marker','v1','endpoint','account','operation','key'):
                        self.assertNotIn('replay', calls)
                    if mode in ('v1','endpoint','account','operation','key'):
                        self.assertEqual(calls, ['prepare'])
    def test_marker_redirect_handler_refuses_redirect(self):
        handler = m.base.NoRedirect()
        self.assertIsNone(handler.redirect_request(None, None, 302, 'redirect', {}, 'https://outside.invalid/'))

    def test_endpoint_binding_precedes_proxy_mutation(self): self.exercise('endpoint')
    def test_account_binding_precedes_proxy_mutation(self): self.exercise('account')
    def test_operation_binding_precedes_proxy_mutation(self): self.exercise('operation')
    def test_key_binding_precedes_proxy_mutation(self): self.exercise('key')

    def test_v1_envelope_cannot_activate_v2_fault(self): self.exercise('v1')

    def test_exact_staged_success(self): self.exercise('success')
    def test_unconfirmed_fault_blocks_replay(self): self.exercise('marker')
    def test_changed_database_is_not_success(self): self.exercise('changed')
    def test_proxy_stop_timeout_never_starts_replacement(self): self.exercise('timeout')


if __name__ == '__main__':
    unittest.main()
