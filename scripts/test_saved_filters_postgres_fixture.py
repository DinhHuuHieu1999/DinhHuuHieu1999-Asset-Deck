"""Offline inventory sort lifecycle contracts; no Docker or database execution."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location('sort_lifecycle_test', Path(__file__).with_name('saved-filters-postgres-fixture.py'))
m = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(m)
r = m.repository


class SavedFiltersFixtureTests(unittest.TestCase):
    def test_fixed_profile_and_four_assertions(self):
        files, prefix, database, env, opt_in, table = r.profile_settings('saved-filters')
        self.assertEqual((prefix, database, env, opt_in, table), (
            'asset-saved-filters-', 'asset_saved_filters_fixture_', 'ASSET_SAVED_FILTERS',
            'isolated-saved-filters-v1', 'asset_saved_filters_fixture_identity'))
        self.assertEqual(files[2], 'backend/src/domains/assets/asset-saved-filter.postgres.spec.ts')
        self.assertIn('backend/migrations/007-asset-saved-filters.sql', files)
        self.assertIn('backend/src/domains/assets/asset-saved-filter.repository.ts', files)
        self.assertEqual(len(files), len(set(files)))

    def test_no_opt_in_has_no_side_effect(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(r.client.Runtime, 'run') as run:
            with self.assertRaises(r.client.Refusal):
                r.execute(Path(folder), SimpleNamespace(execute_synthetic=False, image='sha256:' + 'a'*64), r.client.Runtime(), profile='saved-filters')
            run.assert_not_called()
            self.assertEqual(list(Path(folder).iterdir()), [])

    def test_every_required_file_is_checked_before_commands(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in r.SAVED_FILTER_FILES:
                path = root/name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('synthetic', encoding='utf-8')
            for name in r.SAVED_FILTER_FILES:
                with self.subTest(name=name), patch.object(r.client.Runtime, 'run') as run:
                    path = root/name
                    path.unlink()
                    with self.assertRaises(r.client.Refusal):
                        r.execute(root, SimpleNamespace(execute_synthetic=True, image='sha256:'+'a'*64), r.client.Runtime(), profile='saved-filters')
                    run.assert_not_called()
                    self.assertFalse((root/'.local').exists())
                    path.write_text('synthetic', encoding='utf-8')

    def test_partial_or_skipped_results_are_not_acceptance(self):
        valid = dict(success=True, numPassedTests=4, numTotalTests=4, numFailedTests=0, numPendingTests=0, numRuntimeErrorTestSuites=0, numPassedTestSuites=1)
        r.validate_result(valid, 4)
        for key in valid:
            broken = dict(valid)
            broken[key] = False if key == 'success' else valid[key] + 1
            with self.subTest(key=key), self.assertRaises(r.client.Refusal):
                r.validate_result(broken, 4)

    def test_wrapper_is_fixed_and_bounded(self):
        source = Path(m.__file__).read_text(encoding='utf-8')
        self.assertIn("profile='saved-filters'", source)
        self.assertIn('Runtime(seconds=120)', source)
        self.assertNotIn('add_argument(\'--profile', source)


if __name__ == '__main__':
    unittest.main()
