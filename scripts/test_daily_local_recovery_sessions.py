"""Real-session orchestration with fake process/HTTPS adapters."""
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch
import unittest
from daily_local_recovery_sessions import RecoverySession, RecoverySessions


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.events=[]
        self.lock=SimpleNamespace(held=True)
        def release():self.events.append('release');self.lock.held=False
        self.lock.release=release
        self.launcher=SimpleNamespace(owned=['backend'],timeout=1)
        def stop():self.events.append('stop');self.launcher.owned=[]
        self.launcher.stop=stop
        self.client=SimpleNamespace(create_synthetic_asset=lambda:'asset',
            login_and_assert_asset=lambda asset:self.events.append('login-'+asset))
        self.adapter=SimpleNamespace(processes=SimpleNamespace(children={}))
        self.session=RecoverySession(self.adapter,self.launcher,self.lock,self.client,lambda:120)
    def test_seed_and_restored_login(self):
        self.assertEqual(self.session.seed(),'asset')
        self.assertTrue(self.session.login('asset'))
        self.assertEqual(self.events,['login-asset'])
    def test_close_releases_lock_only_after_stopping(self):
        self.session.close()
        self.assertEqual(self.events,['stop','release'])
        self.assertTrue(self.session.clean())
    def test_failed_stop_retains_lock(self):
        def stop():raise RuntimeError('private failure')
        self.launcher.stop=stop
        with self.assertRaises(RuntimeError):self.session.close()
        self.assertTrue(self.lock.held)
        self.assertFalse(self.session.clean())
    def test_inert_app_closes_before_backend(self):
        events=self.events
        child=SimpleNamespace(poll=lambda:None,stdin=SimpleNamespace(close=lambda:events.append('app-eof')),
            wait=lambda timeout:events.append('app-exit'))
        self.adapter.processes.children['app']=('owned',child)
        self.session.close()
        self.assertEqual(events,['app-eof','app-exit','stop','release'])

    def test_factory_retains_failed_startup_for_cleanup(self):
        cfg={'app':Path('python'),'python':Path('python'),'https_port':29443,
             'state_dir':Path('state')}
        lock=SimpleNamespace(held=False)
        def acquire():lock.held=True
        def release():lock.held=False
        lock.acquire,lock.release=acquire,release
        launcher=SimpleNamespace(owned=[],timeout=30)
        def start():launcher.owned=['backend'];raise RuntimeError('startup failed')
        def stop():launcher.owned=[]
        launcher.start,launcher.stop=start,stop
        runtime=SimpleNamespace(env={},remaining=lambda:120)
        db=SimpleNamespace(assert_owned=lambda:None,password='synthetic',port=29444)
        with patch('daily_local_recovery_sessions.validate_config',return_value=cfg), \
             patch('daily_local_recovery_sessions.backend_environment',return_value={}):
            factory=RecoverySessions(cfg,runtime,client=self.client,
                adapter_factory=lambda *args:self.adapter,
                launcher_factory=lambda adapter:launcher,lock_factory=lambda path:lock)
            with self.assertRaises(RuntimeError):factory.open(db)
            self.assertEqual(len(factory.retained),1)
            self.assertTrue(factory.retained[0].clean())
            factory.close_all()

    def test_factory_refuses_real_app_before_client_creation(self):
        cfg={'app':Path('flutter.exe'),'python':Path('python')}
        with patch('daily_local_recovery_sessions.validate_config',return_value=cfg), \
             patch('daily_local_recovery_sessions.SyntheticClient') as client:
            with self.assertRaises(ValueError):RecoverySessions(cfg,None)
            client.assert_not_called()


class ExtendedSessionTests(unittest.TestCase):
    def test_selected_flags_reach_adapter_and_profile_mismatch_starts_nothing(self):
        from daily_local_profile import EXTENDED
        cfg={'app':Path('python'),'python':Path('python'),'https_port':29443,
             'state_dir':Path('state')}
        lock=SimpleNamespace(held=False,acquire=lambda:None)
        launcher=SimpleNamespace(timeout=30,start=lambda:None)
        environments=[]
        db=SimpleNamespace(profile={'name':EXTENDED},assert_owned=lambda:None,
                           password='synthetic',port=29444)
        with patch('daily_local_recovery_sessions.validate_config',return_value=cfg):
            factory=RecoverySessions(cfg,SimpleNamespace(env={},remaining=lambda:120),
                client=object(),profile=EXTENDED,
                adapter_factory=lambda config,env:environments.append(env),
                launcher_factory=lambda adapter:launcher,lock_factory=lambda path:lock)
            factory.open(db)
            self.assertEqual(environments[0]['ASSET_SAVED_FILTERS_ENABLED'],'true')
            self.assertEqual(environments[0]['ASSET_IMPORT_ENABLED'],'false')
            self.assertEqual(environments[0]['CSRF_ENABLED'],'true')
            db.profile={'name':'base'}
            with self.assertRaisesRegex(ValueError,'profile mismatch'):factory.open(db)
            self.assertEqual(len(environments),1)
