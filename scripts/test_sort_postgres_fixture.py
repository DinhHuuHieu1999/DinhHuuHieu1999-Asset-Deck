"""Offline inventory sort lifecycle contracts; no Docker or database execution."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('sort_lifecycle_test', Path(__file__).with_name('sort-postgres-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)
r = m.repository


class SortFixtureTests(unittest.TestCase):
    def test_fixed_profile_and_four_assertions(self):
        files, prefix, database, env, opt_in, table = r.profile_settings('sort')
        self.assertEqual((prefix, database, env, opt_in, table), (
            'asset-sort-', 'asset_sort_fixture_', 'ASSET_SORT',
            'isolated-sort-v1', 'asset_sort_fixture_identity'))
        self.assertEqual(files[2], 'backend/src/domains/assets/asset-sort.postgres.spec.ts')
        self.assertIn('backend/src/domains/assets/asset-sort.ts', files)
        self.assertIn('backend/migrations/004-asset-dates.sql', files)
        self.assertIn('backend/migrations/005-asset-location.sql', files)
        self.assertEqual(len(files), len(set(files)))

    def test_no_opt_in_has_no_side_effect(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(r.client.Runtime, 'run') as run:
            with self.assertRaises(r.client.Refusal):
                r.execute(Path(folder), SimpleNamespace(execute_synthetic=False, image='sha256:' + 'a'*64), r.client.Runtime(), profile='sort')
            run.assert_not_called()
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_every_required_file_is_checked_before_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in r.SORT_FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic', encoding='utf-8')
            for name in r.SORT_FILES:
                with self.subTest(name=name), patch.object(r.client.Runtime, 'run') as run:
                    path = root/name
                    path.unlink()
                    with self.assertRaises(r.client.Refusal):
                        r.execute(root, SimpleNamespace(execute_synthetic=True, image='sha256:'+'a'*64), r.client.Runtime(), profile='sort')
                    run.assert_not_called()
                    self.assertFalse((root/'.local').exists())
                    path.write_text('synthetic', encoding='utf-8')

    def test_wrapper_is_fixed_and_bounded(self):
        source = Path(m.__file__).read_text(encoding='utf-8')
        self.assertIn("profile='sort'", source)
        self.assertIn('Runtime(seconds=120)', source)
        self.assertNotIn('add_argument(\'--profile', source)


if __name__ == '__main__':
    unittest.main()
