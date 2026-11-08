"""Offline selection profile contracts; no real processes or sockets."""
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

from test_client_https_fixture import fixture, FakeRuntime, arguments


class SelectionProfileTests(unittest.TestCase):
    def test_v2_requires_explicit_selection_base(self):
        for value in (True, 1, None, "true"):
            with self.assertRaises(fixture.Refusal):
                fixture.fixture_files(SimpleNamespace(selection_export_v2_mode=value))

    def test_exclusive_typed_profile(self):
        self.assertFalse(fixture.selection_export_mode(SimpleNamespace()))
        for value in (1, None, 'true'):
            with self.assertRaises(fixture.Refusal):
                fixture.fixture_files(SimpleNamespace(selection_export_mode=value))
        for flag in ('check_mode', 'import_mode', 'dates_mode', 'import_v2_mode',
                     'location_mode', 'export_v3_mode', 'import_v3_mode'):
            with self.subTest(flag=flag):
                args = SimpleNamespace(selection_export_mode=True, **{flag: True})
                with self.assertRaises(fixture.Refusal):
                    fixture.fixture_files(args)

    def test_artifact_closure_and_no_import_migration(self):
        files = fixture.fixture_files(SimpleNamespace(selection_export_mode=True, selection_export_v2_mode=True))
        for suffix in ('', '.config', '.module', '.controller', '.repository'):
            self.assertIn('backend/dist/domains/assets/asset-selection-export-v2' + suffix + '.js', files)
        self.assertIn('backend/migrations/004-asset-dates.sql', files)
        self.assertIn('backend/migrations/005-asset-location.sql', files)
        self.assertNotIn('backend/migrations/003-asset-import.sql', files)
        self.assertNotIn('flutter/lib/api/asset_selection_export.dart',
                         fixture.fixture_files(SimpleNamespace(export_v3_mode=True)))

    def test_missing_each_artifact_refuses_before_tls_or_resource_creation(self):
        args = arguments()
        args.selection_export_mode = True
        args.selection_export_v2_mode = True
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in fixture.fixture_files(args):
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            for name in fixture.fixture_files(args):
                with self.subTest(name=name):
                    target = root/name
                    target.unlink()
                    with patch.object(fixture.socket, 'socket', side_effect=AssertionError('No sockets')), \
                         patch.object(Path, 'read_bytes', side_effect=AssertionError('No TLS reads')), \
                         patch.object(fixture.subprocess, 'run', side_effect=AssertionError('No process')), \
                         patch.object(fixture.subprocess, 'Popen', side_effect=AssertionError('No process')):
                        with self.assertRaises(fixture.Refusal):
                            fixture.preflight(root, args)
                    self.assertFalse((root/'.local').exists())
                    target.write_text('synthetic', encoding='utf-8')

    def test_owned_lifecycle_selects_flag_and_proxy_without_import(self):
        class Runtime(FakeRuntime):
            def start(self, command, cwd, env=None):
                if env is not None:
                    self.backend_env = env
                return super().start(command, cwd, env)
        runtime = Runtime()
        args = arguments()
        args.selection_export_mode = True
        args.selection_export_v2_mode = True
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in fixture.fixture_files(args):
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            with patch.object(fixture.socket, 'socket') as socket, \
                 patch.object(fixture.subprocess, 'run', side_effect=AssertionError('Forbidden process')), \
                 patch.object(fixture.subprocess, 'Popen', side_effect=AssertionError('Forbidden process')):
                socket.return_value.__enter__.return_value.connect_ex.return_value = 1
                fixture.execute(root, args, runtime, lambda *unused: {'status': 'completed'})
            self.assertTrue(runtime.stopped)
        self.assertEqual(runtime.backend_env['ASSET_SELECTION_EXPORT_ENABLED'], 'true')
        self.assertEqual(runtime.backend_env['ASSET_SELECTION_EXPORT_V2_ENABLED'], 'true')
        self.assertEqual(runtime.backend_env['ASSET_CHECK_ENABLED'], 'true')
        for key in ('ASSET_IMPORT_ENABLED', 'ASSET_IMPORT_V2_ENABLED', 'ASSET_IMPORT_V3_ENABLED'):
            self.assertEqual(runtime.backend_env[key], 'false')
        for key in ('ASSET_DATES_ENABLED', 'ASSET_LOCATION_ENABLED', 'ASSET_EXPORT_V3_ENABLED'):
            self.assertEqual(runtime.backend_env[key], 'true')
        proxy = [c for c in runtime.calls if any('client-https-proxy-cli.mjs' in part for part in c)]
        self.assertEqual(len(proxy), 1)
        self.assertEqual(proxy[0][-1], '--selection-export-v2-enabled')


if __name__ == '__main__':
    unittest.main()
