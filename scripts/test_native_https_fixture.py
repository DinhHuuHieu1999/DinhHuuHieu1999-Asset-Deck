"""Offline native contracts; all subprocess and socket operations are guarded."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import time
import unittest
from unittest.mock import MagicMock, patch

spec = importlib.util.spec_from_file_location('native_fixture', Path(__file__).with_name('native-https-fixture.py'))
native = importlib.util.module_from_spec(spec)
spec.loader.exec_module(native)


class NativeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        seed = self.root / 'flutter/tool/native_https_seed.dart'
        seed.parent.mkdir(parents=True)
        seed.write_text('synthetic seed source', encoding='utf-8')
        self.folder = self.root / '.local/windows-candidates/synthetic'
        self.folder.mkdir(parents=True)
        self.files = {}
        for name in ('asset_desk.exe', 'flutter_windows.dll', 'data/icudtl.dat'):
            p = self.folder / name
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(b'synthetic only')
            self.files[name] = hashlib.sha256(p.read_bytes()).hexdigest()
        self.manifest = {'schemaVersion': 1, 'buildMode': 'release',
                         'endpoint': 'https://localhost:19003/api/v1', 'files': self.files}
        self.write_manifest()
        self.args = argparse.Namespace(execute_native=True, execute_synthetic=True, minutes=30,
                                       candidate=str(self.folder / 'asset_desk.exe'), tls_port=19003, dart='dart')
        self.services = [MagicMock(), MagicMock()]
        for service in self.services:
            service.poll.return_value = None
        for target in ('subprocess.run', 'subprocess.Popen', 'socket.socket', 'socket.create_connection'):
            # Modules are loaded by file, not installed as importable packages.
            module, name = target.split('.')
            guard = patch.object(getattr(native.client, module), name, side_effect=AssertionError('Forbidden real IO'))
            guard.start()
            self.addCleanup(guard.stop)

    def test_check_profile_requires_exact_defines_and_exclusive_boolean(self):
        self.args.check_mode = True
        defines = {'ASSET_DESK_ENABLE_ASSET_CHECK': 'true',
                   'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
                   'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        for candidate in (None, {}, dict(defines, ASSET_DESK_ENABLE_IMPORT='true'),
                          dict(defines, ASSET_DESK_ENABLE_ASSET_CHECK='false')):
            self.manifest['buildDefines'] = candidate
            self.write_manifest()
            with self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
        self.manifest['buildDefines'] = defines
        self.write_manifest()
        native.verify_candidate(self.root, self.args)
        for field in ('import_mode', 'location_mode', 'selection_export_mode'):
            setattr(self.args, field, True)
            with self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            setattr(self.args, field, False)
        self.args.check_mode = 'true'
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_check_handoff_remains_pending_and_does_not_prepare_import(self):
        self.args.check_mode = True
        self.manifest['buildDefines'] = {'ASSET_DESK_ENABLE_ASSET_CHECK': 'true',
            'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true', 'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.write_manifest()
        runtime = self.runtime()
        result = self.run_session(runtime)
        handoff = json.loads((self.root/'evidence/operator-handoff.json').read_text())
        self.assertTrue(handoff['checkMode'])
        self.assertEqual(handoff['expectedAssets'], 1)
        self.assertNotIn('importFile', handoff)
        self.assertIn('Only unknown check dates', handoff['instructions'])
        self.assertEqual(result['nativeAcceptance'], 'pending')
        runtime.start.assert_called_once()

    def write_manifest(self):
        (self.folder / 'candidate.json').write_text(json.dumps(self.manifest), encoding='utf-8')

    def runtime(self, seed=None):
        runtime = MagicMock(deadline=time.monotonic() + 2100)
        runtime.run.return_value = json.dumps(seed if seed is not None else {
            'username': 'nsynthetic', 'password': 'Synthetic-only-42!', 'assetName': 'Synthetic native asset'}).encode()
        runtime.start.return_value.poll.return_value = 0
        runtime.start.return_value.returncode = 0
        return runtime

    def run_session(self, runtime):
        folder = self.root / 'evidence'
        folder.mkdir()
        return native.native_session(self.root, self.args, runtime, folder, 'a' * 32, *self.services)

    def test_selection_candidate_requires_exact_defines_and_fixed_seed(self):
        self.args.selection_export_mode = True
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)
        defines = {'ASSET_DESK_ENABLE_SELECTION_EXPORT': 'true',
                   'ASSET_DESK_ENABLE_EXPORT_V3': 'true',
                   'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
                   'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.manifest['buildDefines'] = defines
        self.write_manifest()
        self.assertEqual(native.verify_candidate(self.root, self.args), Path(self.args.candidate))
        self.assertEqual(native.seed_source(self.args), 'flutter/tool/native_export_v3_seed.dart')
        for key in defines:
            self.manifest['buildDefines'] = {k: v for k, v in defines.items() if k != key}
            self.write_manifest()
            with self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
        self.manifest['buildDefines'] = dict(defines, ASSET_DESK_ENABLE_IMPORT='true')
        self.write_manifest()
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_selection_handoff_is_not_an_import_or_manual_pass(self):
        self.args.selection_export_mode = True
        self.manifest['buildDefines'] = {
            'ASSET_DESK_ENABLE_SELECTION_EXPORT': 'true',
            'ASSET_DESK_ENABLE_EXPORT_V3': 'true',
            'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
            'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.write_manifest()
        seed = self.root/'flutter/tool/native_export_v3_seed.dart'
        seed.write_text('synthetic only', encoding='utf-8')
        result = self.run_session(self.runtime())
        handoff = json.loads((self.root/'evidence/operator-handoff.json').read_text())
        self.assertTrue(handoff['selectionExportMode'])
        self.assertEqual(handoff['expectedAssets'], 1)
        self.assertNotIn('importFile', handoff)
        self.assertEqual(result['nativeAcceptance'], 'pending')
        self.assertIn('not a full backup', handoff['instructions'])

    def enable_import_v3(self):
        self.args.import_v3_mode = True
        self.manifest['buildDefines'] = {
            'ASSET_DESK_ENABLE_IMPORT': 'true',
            'ASSET_DESK_ENABLE_IMPORT_V3': 'true',
            'ASSET_DESK_ENABLE_ASSET_DATES': 'true',
            'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true'}
        self.write_manifest()

    def test_import_v3_exact_defines_no_legacy_or_export_flags(self):
        self.enable_import_v3()
        native.verify_candidate(self.root, self.args)
        for key in tuple(self.manifest['buildDefines']):
            value = self.manifest['buildDefines'].pop(key)
            self.write_manifest()
            with self.subTest(key=key), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            self.manifest['buildDefines'][key] = value
        for key in ('ASSET_DESK_ENABLE_IMPORT_V2', 'ASSET_DESK_ENABLE_EXPORT_V3'):
            self.manifest['buildDefines'][key] = 'true'
            self.write_manifest()
            with self.subTest(extra=key), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            del self.manifest['buildDefines'][key]

    def test_import_v3_exclusive_typed_profile(self):
        self.enable_import_v3()
        for field in ('import_mode', 'import_v2_mode', 'location_mode', 'dates_mode', 'export_v3_mode'):
            setattr(self.args, field, True)
            with self.subTest(field=field), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            setattr(self.args, field, False)
        self.args.import_v3_mode = 'true'
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_import_v3_file_and_handoff_preserve_dates_location(self):
        self.enable_import_v3()
        runtime = self.runtime()
        result = self.run_session(runtime)
        handoff = json.loads((self.root / 'evidence/operator-handoff.json').read_text())
        path = Path(handoff['importFile'])
        self.assertEqual(path.name, 'inventory-import-v3-synthetic.json')
        raw = path.read_bytes()
        envelope = json.loads(raw)
        self.assertEqual(envelope['schemaVersion'], 3)
        self.assertEqual(envelope['sha256'], hashlib.sha256(envelope['payload'].encode('utf-8')).hexdigest())
        row = json.loads(envelope['payload'])['records'][0]
        self.assertEqual((row['purchasedOn'], row['warrantyExpiresOn'], row['location']),
                         ('2024-02-29', '2027-02-28', 'Synthetic room %_1'))
        self.assertEqual((handoff['expectedBefore'], handoff['expectedAfter']), (1, 2))
        self.assertEqual(result['nativeAcceptance'], 'pending')
        runtime.start.assert_called_once()
        with self.assertRaises(FileExistsError):
            native.prepare_import_file(path.parent, v3=True)
        self.assertEqual(path.read_bytes(), raw)

    def test_import_file_refuses_mixed_or_untyped_versions_before_writing(self):
        for values in ({'v2': True, 'v3': True}, {'v3': 1}, {'v3': 'true'}):
            with self.subTest(values=values), self.assertRaises(native.client.Refusal):
                native.prepare_import_file(self.root, **values)
        self.assertFalse(list(self.root.glob('inventory-import*.json')))

    def enable_export_v3(self):
        self.args.export_v3_mode = True
        self.manifest['buildDefines'] = {
            'ASSET_DESK_ENABLE_EXPORT_V3': 'true',
            'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
            'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.write_manifest()
        seed = self.root / native.seed_source(self.args)
        seed.write_text('synthetic v3 seed', encoding='utf-8')

    def test_export_v3_exact_defines(self):
        self.enable_export_v3()
        native.verify_candidate(self.root, self.args)
        for key in tuple(self.manifest['buildDefines']):
            old = self.manifest['buildDefines'].pop(key)
            self.write_manifest()
            with self.subTest(key=key), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            self.manifest['buildDefines'][key] = old
        self.manifest['buildDefines']['ASSET_DESK_ENABLE_IMPORT'] = 'true'
        self.write_manifest()
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_export_v3_rejects_mixed_profiles(self):
        self.enable_export_v3()
        for field in ('location_mode', 'dates_mode', 'import_mode', 'import_v2_mode'):
            setattr(self.args, field, True)
            with self.subTest(field=field), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            setattr(self.args, field, False)
        self.args.export_v3_mode = 'true'
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_export_v3_missing_seed_refuses_before_shared_preflight(self):
        self.enable_export_v3()
        (self.root / native.seed_source(self.args)).unlink()
        with patch.object(native.os, 'name', 'nt'), patch.object(native.client, 'preflight') as shared:
            with self.assertRaisesRegex(native.client.Refusal, 'Native seed source missing'):
                native.preflight(self.root, self.args)
            shared.assert_not_called()

    def test_export_v3_seed_and_manual_handoff(self):
        self.enable_export_v3()
        runtime = self.runtime()
        result = self.run_session(runtime)
        command = runtime.run.call_args.args[0]
        self.assertIn(str(self.root / native.seed_source(self.args)), command)
        value = json.loads((self.root / 'evidence/operator-handoff.json').read_text(encoding='utf-8'))
        self.assertTrue(value['exportV3Mode'])
        self.assertEqual(value['expectedAssets'], 1)
        self.assertEqual(value['purchasedOn'], '2024-02-29')
        self.assertEqual(value['warrantyExpiresOn'], '2027-02-28')
        self.assertEqual(value['locationLabel'], 'Synthetic room %_1')
        self.assertNotIn('importFile', value)
        self.assertEqual(result['nativeAcceptance'], 'pending')
        self.assertEqual(result['seedSourceSha256'], hashlib.sha256(b'synthetic v3 seed').hexdigest())

    def test_location_requires_exact_build_defines(self):
        self.args.location_mode = True
        for defines in (None, {}, {'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true'},
                        {'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
                         'ASSET_DESK_ENABLE_ASSET_DATES': 'true',
                         'ASSET_DESK_ENABLE_IMPORT': 'true'}):
            self.manifest['buildDefines'] = defines
            self.write_manifest()
            with self.subTest(defines=defines), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
        self.manifest['buildDefines'] = {
            'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
            'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.write_manifest()
        native.verify_candidate(self.root, self.args)

    def test_location_rejects_mixed_and_untyped_profiles(self):
        for field in ('import_mode', 'import_v2_mode', 'dates_mode'):
            self.args.location_mode = True
            setattr(self.args, field, True)
            with self.subTest(field=field), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            setattr(self.args, field, False)
        self.args.location_mode = 'true'
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_location_handoff_is_manual_and_has_no_import_file(self):
        self.args.location_mode = True
        self.manifest['buildDefines'] = {
            'ASSET_DESK_ENABLE_ASSET_LOCATION': 'true',
            'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.write_manifest()
        result = self.run_session(self.runtime())
        value = json.loads((self.root / 'evidence/operator-handoff.json').read_text(encoding='utf-8'))
        self.assertTrue(value['locationMode'])
        self.assertEqual(value['expectedAssets'], 1)
        self.assertNotIn('importFile', value)
        self.assertEqual(result['nativeAcceptance'], 'pending')

    def test_no_opt_in_refuses_before_file_io(self):
        self.args.execute_native = False
        with patch.object(Path, 'is_file', side_effect=AssertionError('No IO')):
            with self.assertRaises(native.client.Refusal):
                native.preflight(self.root, self.args)

    def test_candidate_exact_inventory_and_endpoint(self):
        self.assertEqual(native.verify_candidate(self.root, self.args), Path(self.args.candidate))
        for field, value in [('endpoint', 'https://localhost:8443/api/v1'), ('buildMode', 'debug'), ('schemaVersion', 2)]:
            old = self.manifest[field]
            self.manifest[field] = value
            self.write_manifest()
            with self.subTest(field=field), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            self.manifest[field] = old
        self.write_manifest()

    def test_mutated_missing_extra_and_traversal_files_refused(self):
        path = self.folder / 'asset_desk.exe'
        path.write_bytes(b'mutated')
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)
        path.write_bytes(b'synthetic only')
        self.manifest['files']['../escape'] = '0' * 64
        self.write_manifest()
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)
        del self.manifest['files']['../escape']
        self.write_manifest()
        extra = self.folder / 'unexpected.dll'
        extra.write_bytes(b'extra')
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_external_candidate_and_duration_refused(self):
        for field, value in [('candidate', str(self.root / 'asset_desk.exe')), ('minutes', 0), ('minutes', 31)]:
            old = getattr(self.args, field)
            setattr(self.args, field, value)
            with self.subTest(field=field), self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
            setattr(self.args, field, old)

    def test_missing_executable_and_required_deployment_are_refused(self):
        path = self.folder / 'asset_desk.exe'
        path.unlink()
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)
        path.write_bytes(b'synthetic only')
        del self.manifest['files']['flutter_windows.dll']
        self.write_manifest()
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_reparse_directory_refused_without_launch(self):
        original = Path.stat
        def stat(path, *args, **kwargs):
            value = original(path, *args, **kwargs)
            if path == self.folder:
                value = MagicMock(st_file_attributes=1024, st_mode=value.st_mode)
            return value
        with patch.object(Path, 'stat', stat), self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_seed_failure_never_launches_or_writes_handoff(self):
        runtime = self.runtime()
        runtime.run.side_effect = native.client.Refusal('Synthetic TLS failure')
        with self.assertRaises(native.client.Refusal):
            self.run_session(runtime)
        runtime.start.assert_not_called()
        self.assertFalse((self.root / 'evidence/operator-handoff.json').exists())

    def test_malformed_seed_never_launches(self):
        for seed in ({}, {'username': 'x', 'password': 'x', 'assetName': 'wrong'}, []):
            runtime = self.runtime(seed)
            with tempfile.TemporaryDirectory() as directory:
                with self.subTest(seed=seed), self.assertRaises(native.client.Refusal):
                    native.native_session(self.root, self.args, runtime, Path(directory), 'a' * 32, *self.services)
            runtime.start.assert_not_called()

    def test_private_handoff_and_exact_launch_do_not_imply_acceptance(self):
        runtime = self.runtime()
        result = self.run_session(runtime)
        self.assertEqual(result['nativeAcceptance'], 'pending')
        self.assertEqual(result['status'], 'session-ended')
        self.assertEqual(result['sessionEnd'], 'app-closed')
        runtime.start.assert_called_once_with([self.args.candidate], self.folder)
        command = runtime.run.call_args[0][0]
        self.assertIn('--disable-dart-dev', command)
        self.assertEqual(command[-2:], ['https://localhost:19003/api/v1', 'a' * 32])
        handoff = json.loads((self.root / 'evidence/operator-handoff.json').read_text())
        self.assertTrue(handoff['syntheticOnly'])
        self.assertEqual(handoff['fixtureId'], 'a' * 32)

    def test_failed_app_and_dead_service_fail_closed(self):
        runtime = self.runtime()
        runtime.start.return_value.returncode = 1
        with self.assertRaises(native.client.Refusal):
            self.run_session(runtime)
        self.services[0].poll.return_value = 1
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(native.client.Refusal):
                native.native_session(self.root, self.args, self.runtime(), Path(directory), 'a' * 32, *self.services)

    def test_hold_is_bounded_without_retry(self):
        runtime = self.runtime()
        runtime.start.return_value.poll.return_value = None
        self.args.minutes = 1
        with patch.object(native.time, 'monotonic', side_effect=[0, 0, 1, 61]), patch.object(native.time, 'sleep'):
            result = self.run_session(runtime)
        self.assertEqual(result['sessionEnd'], 'deadline')
        runtime.run.assert_called_once()
        runtime.start.assert_called_once()

    def test_v2_profile_requires_all_exact_build_flags_and_refuses_mixed_modes(self):
        self.args.import_v2_mode = True
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)
        self.manifest['buildDefines'] = {'ASSET_DESK_ENABLE_IMPORT': 'true',
                                        'ASSET_DESK_ENABLE_IMPORT_V2': 'true',
                                        'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.write_manifest()
        self.assertEqual(native.verify_candidate(self.root, self.args), Path(self.args.candidate))
        self.args.import_mode = True
        with self.assertRaises(native.client.Refusal):
            native.verify_candidate(self.root, self.args)

    def test_v2_synthetic_file_retains_dates_and_checksum(self):
        folder = self.root / 'v2-file'
        folder.mkdir()
        path = native.prepare_import_file(folder, v2=True)
        envelope = json.loads(path.read_text(encoding='utf-8'))
        self.assertEqual(envelope['schemaVersion'], 2)
        self.assertEqual(envelope['sha256'], hashlib.sha256(envelope['payload'].encode()).hexdigest())
        record = json.loads(envelope['payload'])['records'][0]
        self.assertEqual(record['purchasedOn'], '2024-02-29')
        self.assertEqual(record['warrantyExpiresOn'], '2027-02-28')
        with self.assertRaises(FileExistsError):
            native.prepare_import_file(folder, v2=True)

    def test_import_profile_requires_exact_build_metadata(self):
        self.args.import_mode = True
        for value in (None, {}, {'ASSET_DESK_ENABLE_IMPORT': True},
                      {'ASSET_DESK_ENABLE_IMPORT': 'false'}):
            self.manifest['buildDefines'] = value
            self.write_manifest()
            with self.assertRaises(native.client.Refusal):
                native.verify_candidate(self.root, self.args)
        self.manifest['buildDefines'] = {'ASSET_DESK_ENABLE_IMPORT': 'true'}
        self.write_manifest()
        self.assertEqual(native.verify_candidate(self.root, self.args), Path(self.args.candidate))

    def test_synthetic_import_envelope_exact_checksum_and_no_overwrite(self):
        folder = self.root / 'import-file'
        folder.mkdir()
        path = native.prepare_import_file(folder)
        raw = path.read_bytes()
        self.assertFalse(raw.startswith(b'\xef\xbb\xbf'))
        envelope = json.loads(raw)
        self.assertEqual(set(envelope), {'format', 'schemaVersion', 'payload', 'sha256'})
        self.assertEqual(envelope['sha256'], hashlib.sha256(envelope['payload'].encode()).hexdigest())
        payload = json.loads(envelope['payload'])
        self.assertEqual(payload['recordCount'], 1)
        self.assertEqual(len(payload['records']), 1)
        self.assertEqual(payload['records'][0]['name'], 'Synthetic native imported asset')
        with self.assertRaises(FileExistsError):
            native.prepare_import_file(folder)
        self.assertEqual(path.read_bytes(), raw)

    def test_import_handoff_has_file_but_still_requires_operator_acceptance(self):
        self.args.import_mode = True
        self.manifest['buildDefines'] = {'ASSET_DESK_ENABLE_IMPORT': 'true'}
        self.write_manifest()
        runtime = self.runtime()
        result = self.run_session(runtime)
        handoff = json.loads((self.root/'evidence/operator-handoff.json').read_text())
        self.assertEqual(handoff['expectedBefore'], 1)
        self.assertEqual(handoff['expectedAfter'], 2)
        self.assertTrue(Path(handoff['importFile']).is_file())
        self.assertEqual(result['nativeAcceptance'], 'pending')
        runtime.start.assert_called_once()

    def test_v2_handoff_uses_date_aware_file_without_claiming_acceptance(self):
        self.args.import_v2_mode = True
        self.manifest['buildDefines'] = {'ASSET_DESK_ENABLE_IMPORT': 'true',
                                        'ASSET_DESK_ENABLE_IMPORT_V2': 'true',
                                        'ASSET_DESK_ENABLE_ASSET_DATES': 'true'}
        self.write_manifest()
        runtime = self.runtime()
        result = self.run_session(runtime)
        handoff = json.loads((self.root/'evidence/operator-handoff.json').read_text())
        path = Path(handoff['importFile'])
        self.assertEqual(path.name, 'inventory-import-v2-synthetic.json')
        self.assertEqual(json.loads(path.read_text())['schemaVersion'], 2)
        self.assertEqual((handoff['expectedBefore'], handoff['expectedAfter']), (1, 2))
        self.assertEqual(result['nativeAcceptance'], 'pending')
        runtime.start.assert_called_once()


if __name__ == '__main__':
    unittest.main()
