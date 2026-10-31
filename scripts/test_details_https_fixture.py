"""Offline details TLS contracts; never invoke network or subprocesses."""
import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('details_tls_test', Path(__file__).with_name('details-https-fixture.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class DetailsHttpsTests(unittest.TestCase):
    def test_exact_result_only(self):
        good = dict(status='completed', syntheticOnly=True, detailsAcceptance=True, owners=2, readOnlySnapshots=2)
        m.validate_dart_result(good)
        for value in (None, {}, dict(good, owners=True), dict(good, syntheticOnly=1), dict(good, detailsAcceptance=1), dict(good, detailsAcceptance=False), dict(good, extra=True)):
            with self.assertRaises(m.client.Refusal):
                m.validate_dart_result(value)

    def test_single_driver_and_no_retry(self):
        args = SimpleNamespace(dart='dart', tls_port=29443)
        result = b'{"status":"completed","syntheticOnly":true,"detailsAcceptance":true,"owners":2,"readOnlySnapshots":2}'
        with patch.object(m, 'source_hashes', return_value={'source': 'same'}), patch.object(m.client.Runtime, 'run', return_value=result) as run:
            m.acceptance(Path('synthetic'), args, m.client.Runtime(), None, 'a'*32, None, None)
            self.assertEqual(run.call_count, 1)
            self.assertIn('details_https_acceptance.dart', run.call_args.args[0][2])

    def test_changed_source_and_incomplete_result_refused(self):
        args = SimpleNamespace(dart='dart', tls_port=29443)
        with patch.object(m, 'source_hashes', return_value={}), patch.object(m.client.Runtime, 'run', return_value=b'{}') as run:
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('synthetic'), args, m.client.Runtime(), None, 'a'*32, None, None)
            self.assertEqual(run.call_count, 1)

    def test_source_change_refused(self):
        args = SimpleNamespace(dart='dart', tls_port=29443)
        result = b'{"status":"completed","syntheticOnly":true,"detailsAcceptance":true,"owners":2,"readOnlySnapshots":2}'
        with patch.object(m, 'source_hashes', side_effect=[{'x': 'before'}, {'x': 'after'}]), patch.object(m.client.Runtime, 'run', return_value=result) as run:
            with self.assertRaises(m.client.Refusal):
                m.acceptance(Path('synthetic'), args, m.client.Runtime(), None, 'a'*32, None, None)
            self.assertEqual(run.call_count, 1)

    def test_cli_binds_details_profile_and_restores_shared_state(self):
        original_files = m.shared.FILES
        original_acceptance = m.shared.acceptance
        def invoke():
            self.assertEqual(m.shared.FILES, m.FILES)
            self.assertIs(m.shared.acceptance, m.acceptance)
            return 1
        with patch.object(m.shared, 'main', side_effect=invoke) as main:
            self.assertEqual(m.main(), 1)
            main.assert_called_once_with()
        self.assertEqual(m.shared.FILES, original_files)
        self.assertIs(m.shared.acceptance, original_acceptance)
        with patch.object(m.shared, 'main', side_effect=OSError('synthetic failure')):
            with self.assertRaises(OSError):
                m.main()
        self.assertEqual(m.shared.FILES, original_files)
        self.assertIs(m.shared.acceptance, original_acceptance)


if __name__ == '__main__':
    unittest.main()
