"""Offline check-date TLS profile contracts; no Docker, TLS or process execution."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('check_tls_contract', Path(__file__).with_name('client-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class CheckProfileTests(unittest.TestCase):
    def test_wrapper_result_is_exact_and_typed(self):
        spec = importlib.util.spec_from_file_location('check_tls_wrapper', Path(__file__).with_name('check-https-fixture.py'))
        wrapper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(wrapper)
        valid = dict(status='completed', syntheticOnly=True, checkDateAcceptance=True,
                     owners=2, nativeDialog='not-exercised')
        wrapper.validate_result(valid)
        for value in (dict(valid, owners=True), dict(valid, owners=1),
                      dict(valid, unexpected=True), dict(valid, status='failed')):
            with self.assertRaises(wrapper.client.Refusal):
                wrapper.validate_result(value)
        self.assertEqual(len(wrapper.FILES), len(set(wrapper.FILES)))

    def test_acceptance_runs_once_and_refuses_changed_source(self):
        spec = importlib.util.spec_from_file_location('check_tls_acceptance', Path(__file__).with_name('check-https-fixture.py'))
        wrapper = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(wrapper)
        valid = dict(status='completed', syntheticOnly=True, checkDateAcceptance=True,
                     owners=2, nativeDialog='not-exercised')
        import json
        from unittest.mock import MagicMock
        args = SimpleNamespace(dart='synthetic-dart', tls_port=29502)
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            runtime = MagicMock()
            runtime.run.return_value = json.dumps(valid)
            with patch.object(wrapper, 'source_hashes', side_effect=[{'source': 'a'}, {'source': 'a'}]):
                result = wrapper.acceptance(root, args, runtime, root, 'a'*32, None, None)
            self.assertTrue(result['checkDateDartClient'])
            runtime.run.assert_called_once()
            command = runtime.run.call_args.args[0]
            self.assertEqual(command[-3:], ['--synthetic-only', 'https://localhost:29502/api/v1', 'a'*32])
            runtime.reset_mock()
            with patch.object(wrapper, 'source_hashes', side_effect=[{'source': 'a'}, {'source': 'b'}]):
                with self.assertRaises(wrapper.client.Refusal):
                    wrapper.acceptance(root, args, runtime, root, 'a'*32, None, None)
            runtime.run.assert_called_once()
            runtime.reset_mock()
            runtime.run.return_value = json.dumps(dict(valid, owners=1))
            with patch.object(wrapper, 'source_hashes', return_value={'source': 'a'}):
                with self.assertRaises(wrapper.client.Refusal):
                    wrapper.acceptance(root, args, runtime, root, 'a'*32, None, None)
            runtime.run.assert_called_once()

    def test_profile_requires_an_exact_boolean(self):
        self.assertFalse(m.check_mode(SimpleNamespace()))
        self.assertTrue(m.check_mode(SimpleNamespace(check_mode=True)))
        for value in ('true', 1, None, []):
            with self.assertRaises(m.Refusal):
                m.fixture_files(SimpleNamespace(check_mode=value))

    def test_other_profiles_cannot_be_combined(self):
        for name in ('import_mode', 'dates_mode', 'import_v2_mode', 'location_mode', 'export_v3_mode', 'import_v3_mode', 'selection_export_mode'):
            with self.assertRaises(m.Refusal):
                m.fixture_files(SimpleNamespace(check_mode=True, **{name: True}))

    def test_fixed_dependencies_include_check_location_and_dates_but_not_import(self):
        files = m.fixture_files(SimpleNamespace(check_mode=True))
        self.assertIn('backend/migrations/005-asset-location.sql', files)
        self.assertIn('backend/migrations/006-asset-check.sql', files)
        self.assertIn('backend/dist/domains/assets/asset-check.module.js', files)
        self.assertIn('backend/migrations/004-asset-dates.sql', files)
        self.assertIn('flutter/tool/check_https_acceptance.dart', files)
        self.assertNotIn('backend/migrations/003-asset-import.sql', files)
        self.assertEqual(len(files), len(set(files)))

    def test_missing_each_profile_file_refuses_before_commands_or_directory_creation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            files = m.fixture_files(SimpleNamespace(check_mode=True))
            for name in files:
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            for name in files:
                target = root/name
                target.unlink()
                args = SimpleNamespace(check_mode=True, execute_synthetic=True, image='sha256:'+'b'*64)
                with patch.object(m.Runtime, 'run') as run:
                    with self.assertRaises(m.Refusal):
                        m.preflight(root, args)
                    run.assert_not_called()
                self.assertFalse((root/'.local').exists())
                target.write_text('synthetic', encoding='utf-8')

    def test_profile_without_driver_refuses_before_resources(self):
        with patch.object(m.Runtime, 'run') as run:
            with self.assertRaises(m.Refusal):
                m.execute(Path('.'), SimpleNamespace(check_mode=True), m.Runtime())
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
