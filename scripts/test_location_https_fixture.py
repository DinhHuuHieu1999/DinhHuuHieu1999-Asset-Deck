"""Offline location TLS profile contracts; no Docker, TLS or process execution."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('location_tls_contract', Path(__file__).with_name('client-https-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)


class LocationProfileTests(unittest.TestCase):
    def test_profile_requires_an_exact_boolean(self):
        self.assertFalse(m.location_mode(SimpleNamespace()))
        self.assertTrue(m.location_mode(SimpleNamespace(location_mode=True)))
        for value in ('true', 1, None, []):
            with self.assertRaises(m.Refusal):
                m.fixture_files(SimpleNamespace(location_mode=value))

    def test_other_profiles_cannot_be_combined(self):
        for name in ('import_mode', 'dates_mode', 'import_v2_mode'):
            with self.assertRaises(m.Refusal):
                m.fixture_files(SimpleNamespace(location_mode=True, **{name: True}))

    def test_fixed_dependencies_include_location_and_dates_but_not_import(self):
        files = m.fixture_files(SimpleNamespace(location_mode=True))
        self.assertIn('backend/migrations/005-asset-location.sql', files)
        self.assertIn('backend/migrations/004-asset-dates.sql', files)
        self.assertIn('flutter/tool/location_https_acceptance.dart', files)
        self.assertNotIn('backend/migrations/003-asset-import.sql', files)
        self.assertEqual(len(files), len(set(files)))

    def test_missing_each_profile_file_refuses_before_commands_or_directory_creation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            files = m.fixture_files(SimpleNamespace(location_mode=True))
            for name in files:
                target = root/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('synthetic', encoding='utf-8')
            for name in files:
                target = root/name
                target.unlink()
                args = SimpleNamespace(location_mode=True, execute_synthetic=True, image='sha256:'+'b'*64)
                with patch.object(m.Runtime, 'run') as run:
                    with self.assertRaises(m.Refusal):
                        m.preflight(root, args)
                    run.assert_not_called()
                self.assertFalse((root/'.local').exists())
                target.write_text('synthetic', encoding='utf-8')

    def test_profile_without_driver_refuses_before_resources(self):
        with patch.object(m.Runtime, 'run') as run:
            with self.assertRaises(m.Refusal):
                m.execute(Path('.'), SimpleNamespace(location_mode=True), m.Runtime())
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
