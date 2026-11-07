"""Recovery contracts with synthetic bytes only; no Docker or networking."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from daily_local_recovery import verify_base_restore


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.folder = Path(self.temp.name)
        self.calls = []
        self.empty = b'0'
        self.dump = b'PGDMPsynthetic'
        self.bad_target = False
        self.owner = True
        self.tables = b'assets.assets\nauth.accounts\n'
        def owned():
            if not self.owner: raise ValueError('ownership')
        def run(command, **kwargs):
            self.calls.append((command, kwargs))
            if 'pg_restore' in command: return b''
            if 'pg_dump' in command: return self.dump
            if any('schemaname ||' in value for value in command): return self.tables
            if any('pg_tables' in value for value in command): return self.empty
            row = {'id': 'synthetic', 'private': 'never-in-report'}
            if self.bad_target and 'asset-daily-' + 'b' * 32 in command: row['id'] = 'changed'
            return json.dumps([row]).encode()
        self.source, self.target = [SimpleNamespace(identity=c*32,
            name='asset-daily-'+c*32, assert_owned=owned,
            runtime=SimpleNamespace(run=run)) for c in ('a','b')]
    def verify(self, login=lambda db: True):
        return verify_base_restore(self.source,self.target,self.folder,lambda:120,login)
    def test_success_exact_restore_and_redaction(self):
        result=self.verify()
        self.assertEqual(result['status'],'completed')
        self.assertNotIn('never-in-report',json.dumps(result))
        command,kw=next(call for call in self.calls if 'pg_restore' in call[0])
        self.assertIn('--exit-on-error',command)
        self.assertNotIn('--clean',command)
        self.assertEqual(kw['data'],self.dump)
    def test_same_target_refused_before_commands(self):
        self.target=self.source
        with self.assertRaises(ValueError):self.verify()
        self.assertEqual(self.calls,[])
    def test_existing_artifact_not_overwritten(self):
        p=self.folder/'daily-base.dump';p.write_bytes(b'keep')
        with self.assertRaises(ValueError):self.verify()
        self.assertEqual(p.read_bytes(),b'keep')
        self.assertEqual(self.calls,[])
    def test_nonempty_target_never_restored(self):
        self.empty=b'1'
        with self.assertRaises(ValueError):self.verify()
        self.assertFalse(any('pg_restore' in c for c,_ in self.calls))
    def test_ownership_failure_starts_no_command(self):
        self.owner=False
        with self.assertRaises(ValueError):self.verify()
        self.assertEqual(self.calls,[])
    def test_invalid_dump_not_saved(self):
        self.dump=b'not-a-dump'
        with self.assertRaises(ValueError):self.verify()
        self.assertFalse((self.folder/'daily-base.dump').exists())
    def test_comparison_failure_retains_dump_without_success_manifest(self):
        self.bad_target=True
        with self.assertRaises(ValueError):self.verify()
        self.assertTrue((self.folder/'daily-base.dump').exists())
        self.assertFalse((self.folder/'daily-base-manifest.json').exists())
    def test_failed_login_not_success(self):
        with self.assertRaises(ValueError):self.verify(lambda db: False)
        self.assertFalse((self.folder/'daily-base-manifest.json').exists())

    def test_optional_tables_refused_before_dump(self):
        self.tables += b'assets.saved_filters\n'
        with self.assertRaisesRegex(ValueError, 'base-profile'): self.verify()
        self.assertFalse(any('pg_dump' in c for c,_ in self.calls))
    def test_expired_deadline_before_commands(self):
        def expired(): raise TimeoutError('deadline')
        with self.assertRaises(TimeoutError):
            verify_base_restore(self.source,self.target,self.folder,expired,lambda db:True)
        self.assertEqual(self.calls,[])
    def test_restore_command_failure_has_no_success_manifest(self):
        original=self.target.runtime.run
        def run(command,**kwargs):
            if 'pg_restore' in command: raise RuntimeError('private simulated error')
            return original(command,**kwargs)
        self.target.runtime.run=run
        with self.assertRaises(RuntimeError): self.verify()
        self.assertTrue((self.folder/'daily-base.dump').exists())
        self.assertFalse((self.folder/'daily-base-manifest.json').exists())
