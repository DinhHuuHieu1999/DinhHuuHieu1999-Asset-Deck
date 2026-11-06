"""Offline exact-handle restart contracts; no process, TLS or socket operations."""
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location('saved_restart_fixture', Path(__file__).with_name('saved-filters-restart-https-fixture.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class RestartTests(unittest.TestCase):
    def test_unknown_stage_never_starts_process(self):
        runtime = Mock()
        with self.assertRaises(m.client.Refusal):
            m.stage(Path('.'), SimpleNamespace(), runtime, Path('.'), 'a'*32, 'other')
        runtime.run.assert_not_called()

    def test_each_restart_source_is_required_before_base_preflight(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in m.FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic')
            for name in m.FILES:
                path = root/name
                path.unlink()
                with patch.object(m.base, 'preflight') as base:
                    with self.assertRaises(m.client.Refusal):
                        m.preflight(root, SimpleNamespace())
                    base.assert_not_called()
                path.write_text('synthetic')

    def test_partial_or_wrong_typed_stage_is_refused(self):
        args = SimpleNamespace(dart='dart', tls_port=29443)
        good = dict(status='completed', stage='prepare', syntheticOnly=True, owners=2)
        for value in ({}, dict(good, owners=True), dict(good, syntheticOnly=1), dict(good, stage='verify')):
            runtime = Mock()
            runtime.run.return_value = json.dumps(value).encode()
            with self.assertRaises(m.client.Refusal):
                m.stage(Path('.'), args, runtime, Path('.'), 'a'*32, 'prepare')

    def test_no_opt_in_refuses_without_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            runtime = m.client.Runtime()
            with patch.object(runtime, 'run') as run:
                with self.assertRaises(m.client.Refusal):
                    m.preflight(Path(folder), SimpleNamespace(execute_synthetic=False))
                run.assert_not_called()
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_owned_restart_reuses_launch_and_checks_new_readiness(self):
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp)
            runtime = m.client.Runtime()
            child = Mock(pid=123)
            child.poll.return_value = None
            command = ['node', '--require', 'x/client-https-backend.cjs', 'backend/dist/main.js']
            env = dict(ASSET_DESK_FIXTURE_ID='a'*32, BACKEND_HTTP_PORT='29442')
            runtime.children.append(child)
            runtime.launches[child] = (command, folder, env)
            marker = folder/'backend-ready.json'
            marker.write_text(json.dumps(dict(fixtureId='a'*32, port=29442, pid=123)))
            replacement = Mock()
            with patch.object(runtime, 'start', return_value=replacement) as start, patch.object(runtime, 'wait_backend') as ready:
                self.assertIs(runtime.restart_backend(folder, 'a'*32, 29442, child), replacement)
                start.assert_called_once_with(command, folder, env)
                ready.assert_called_once_with(folder, 'a'*32, 29442, replacement)
            child.terminate.assert_called_once()
            self.assertFalse(marker.exists())

    def test_foreign_handle_or_marker_cannot_be_stopped(self):
        for owned in (False, True):
            with tempfile.TemporaryDirectory() as temp:
                folder = Path(temp)
                runtime = m.client.Runtime()
                child = Mock(pid=123)
                child.poll.return_value = None
                if owned:
                    runtime.children.append(child)
                    runtime.launches[child] = (['node', '--require', 'client-https-backend.cjs', 'main.js'], folder,
                        dict(ASSET_DESK_FIXTURE_ID='a'*32, BACKEND_HTTP_PORT='29442'))
                    (folder/'backend-ready.json').write_text(json.dumps(dict(fixtureId='b'*32, port=29442, pid=123)))
                with self.assertRaises(m.client.Refusal):
                    runtime.restart_backend(folder, 'a'*32, 29442, child)
                child.terminate.assert_not_called()

    def test_acceptance_order_and_stop_on_prepare_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in m.FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic')
            runtime = Mock()
            args = SimpleNamespace(backend_port=29442)
            with patch.object(m, 'stage', side_effect=m.client.Refusal('failed')), patch.object(m.client, 'assert_owned'):
                with self.assertRaises(m.client.Refusal):
                    m.acceptance(root,args,runtime,root,'a'*32,Mock(),Mock())
            runtime.restart_backend.assert_not_called()

    def test_success_requires_prepare_restart_verify_in_order(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for name in m.FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic')
            events = []
            runtime = Mock()
            runtime.restart_backend.side_effect = lambda *args: events.append('restart')
            with patch.object(m, 'stage', side_effect=lambda *args: events.append(args[-1])), patch.object(m.client, 'assert_owned'):
                result = m.acceptance(root,SimpleNamespace(backend_port=29442),runtime,root,'a'*32,Mock(),Mock())
            self.assertEqual(events, ['prepare', 'restart', 'verify'])
            self.assertIs(result['savedFiltersBackendRestart'], True)


if __name__ == '__main__':
    unittest.main()
