"""Bootstrap contracts; every OS adapter is fake."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
from daily_local_recovery_fixture import execute,preflight


class BootstrapTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name).resolve()
        self.args=SimpleNamespace(restore_port=29446,db_port=29444,backend_port=29445,tls_port=29443,
            candidate=str(self.root/'candidate'),cert=str(self.root/'cert'),key=str(self.root/'key'),image='pin')
        self.runtime=SimpleNamespace(remaining=lambda:120,deadline=0)
        self.events=[];self.fail_accept=False;self.fail_cleanup=False
    def execute(self):
        events=self.events
        def database(runtime,image,port,identity):
            return SimpleNamespace(stop=lambda:events.append('db-stop'),port=port)
        def sessions(config,runtime):
            def close():
                events.append('sessions-close')
                if self.fail_cleanup:raise RuntimeError('private')
            return SimpleNamespace(close_all=close)
        def accept(*args,**kwargs):
            self.assertFalse(kwargs['cleanup_databases'])
            events.append('accept')
            if self.fail_accept:raise RuntimeError('private')
        with patch('daily_local_recovery_fixture.preflight'),patch('shutil.which',return_value=str(self.root/'node')):
            return execute(self.root,self.args,self.runtime,database_factory=database,
                sessions_factory=sessions,accept=accept,ports_free=lambda ports:None)
    def result(self):
        p=next((self.root/'.local').glob('daily-recovery-*/result.json'))
        return json.loads(p.read_text())
    def test_success_requires_cleanup(self):
        self.assertEqual(self.execute()['status'],'completed')
        self.assertEqual(self.events,['accept','sessions-close','db-stop','db-stop'])
        self.assertEqual(self.result()['cleanup'],'stopped')
    def test_acceptance_failure_retained_and_cleaned(self):
        self.fail_accept=True
        with self.assertRaises(RuntimeError):self.execute()
        self.assertEqual(self.result()['status'],'failed')
        self.assertNotIn('private',json.dumps(self.result()))
        self.assertEqual(self.events[-2:],['db-stop','db-stop'])
    def test_session_cleanup_failure_preserves_databases(self):
        self.fail_cleanup=True
        with self.assertRaises(RuntimeError):self.execute()
        self.assertNotIn('db-stop',self.events)
        self.assertEqual(self.result()['cleanup'],'incomplete')
    def test_invalid_restore_port_before_writes(self):
        with patch('daily_local_recovery_fixture.runtime_preflight'):
            for value in (True,28443,29443,29444,29445,0):
                self.args.restore_port=value
                with self.assertRaises(ValueError):preflight(self.root,self.args)
        self.assertFalse((self.root/'.local').exists())
