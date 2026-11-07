"""Recovery orchestration with fake lifecycle objects only."""
from types import SimpleNamespace
import unittest
from daily_local_recovery_acceptance import accept_recovery


class AcceptanceTests(unittest.TestCase):
    def setUp(self):
        self.events=[]
        self.fail_seed=False
        self.fail_stop=False
        self.unclean=False
        def database(name):
            def stop():
                self.events.append(name+'-stop')
                if self.fail_stop:raise ValueError('private error')
            return SimpleNamespace(identity=name,create=lambda:self.events.append(name+'-create'),
                wait_ready=lambda:None,migrate=lambda root:self.events.append(name+'-migrate'),stop=stop)
        self.source,self.target=database('source'),database('target')
        def opened(db):
            self.events.append(db.identity+'-open')
            def seed():
                if self.fail_seed:raise ValueError('seed failed')
                self.events.append('seed');return 'asset'
            return SimpleNamespace(seed=seed,login=lambda asset:self.events.append('login-'+asset) or True,
                close=lambda:self.events.append(db.identity+'-close'),clean=lambda:not self.unclean)
        self.sessions=SimpleNamespace(open=opened)
    def run_acceptance(self):
        def verify(source,target,folder,remaining,login):
            self.events.append('restore')
            self.assertTrue(login(target))
            return {'status':'completed'}
        return accept_recovery(self.source,self.target,None,None,self.sessions,lambda:120,verify)
    def test_source_stopped_before_restore_target_unmigrated(self):
        self.assertEqual(self.run_acceptance()['status'],'completed')
        self.assertLess(self.events.index('source-close'),self.events.index('restore'))
        self.assertNotIn('target-migrate',self.events)
        self.assertIn('login-asset',self.events)
        self.assertEqual(self.events[-2:],['target-stop','source-stop'])
    def test_seed_failure_still_closes_session_and_both_databases(self):
        self.fail_seed=True
        with self.assertRaises(ValueError):self.run_acceptance()
        self.assertIn('source-close',self.events)
        self.assertEqual(self.events[-2:],['target-stop','source-stop'])
    def test_unclean_source_never_restores(self):
        self.unclean=True
        with self.assertRaises(RuntimeError):self.run_acceptance()
        self.assertNotIn('restore',self.events)
    def test_stop_failure_not_pass(self):
        self.fail_stop=True
        with self.assertRaisesRegex(RuntimeError,'cleanup incomplete'):self.run_acceptance()
        self.assertEqual(self.events[-2:],['target-stop','source-stop'])
    def test_same_identity_starts_nothing(self):
        self.target.identity=self.source.identity
        with self.assertRaises(ValueError):self.run_acceptance()
        self.assertEqual(self.events,[])
