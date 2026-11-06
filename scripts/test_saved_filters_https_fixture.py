"""Offline saved-filter HTTPS gates; no processes, TLS reads or sockets."""
import importlib.util
import json
from unittest.mock import patch
from pathlib import Path
from types import SimpleNamespace
import unittest

spec = importlib.util.spec_from_file_location('saved_tls', Path(__file__).with_name('saved-filters-https-fixture.py'))
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class SavedHttpsTests(unittest.TestCase):
    def test_exact_result(self):
        good = dict(status='completed', syntheticOnly=True, savedFiltersAcceptance=True, owners=2, mutations=3)
        m.validate_dart_result(good)
        for bad in [dict(good, syntheticOnly=1), dict(good, savedFiltersAcceptance=1), dict(good, owners=True), dict(good, mutations=2), dict(good, extra=True), {}, None]:
            with self.assertRaises(m.client.Refusal): m.validate_dart_result(bad)

    def test_profile_refuses_implicit_or_non_boolean_selection(self):
        for args in [SimpleNamespace(saved_filters_mode=True), SimpleNamespace(saved_filters_mode='true')]:
            with self.assertRaises(m.client.Refusal): m.client.saved_filters_mode(args)
        self.assertFalse(m.client.saved_filters_mode(SimpleNamespace()))
        self.assertTrue(m.client.saved_filters_mode(SimpleNamespace(saved_filters_mode=True,check_mode=True)))

    def test_wrapper_requires_schema_driver_and_fixed_profile(self):
        self.assertIn('backend/migrations/007-asset-saved-filters.sql',m.FILES)
        self.assertEqual(m.FILES[0],'flutter/tool/saved_filters_https_acceptance.dart')
        source=Path(m.__file__).read_text(encoding='utf-8')
        self.assertIn('args.saved_filters_mode = True',source)
        self.assertNotIn('badCertificateCallback',source)


    def test_security_requests_are_marker_bound_and_omit_csrf_on_mutations(self):
        requests = []
        identity = 'a'*32
        class Response:
            def __init__(self,status,body): self.status,self.body=status,body
            def __enter__(self): return self
            def __exit__(self,*args): return False
            def read(self,size): return json.dumps(self.body).encode()
        class Opener:
            def open(self,req,timeout):
                requests.append(req)
                path=m.urllib.parse.urlparse(req.full_url).path
                if path.startswith('/__asset_desk_fixture/'):
                    return Response(200,dict(fixtureId=identity,syntheticOnly=True))
                if path.endswith('/csrf-token'): return Response(200,dict(token='synthetic-csrf'))
                if path.endswith('/register'):
                    self_outer.assertEqual(req.get_header('X-csrf-token'),'synthetic-csrf')
                    return Response(201,dict(accessToken='synthetic-token'))
                if not req.get_header('Authorization'): return Response(401,{})
                if req.method != 'GET':
                    self_outer.assertIsNone(req.get_header('X-csrf-token'))
                    return Response(403,{})
                return Response(200,dict(items=[]))
        self_outer=self
        with patch.object(m.urllib.request,'build_opener',return_value=Opener()):
            m.security_acceptance(SimpleNamespace(tls_port=29443),SimpleNamespace(remaining=lambda:30),identity)
        self.assertEqual(len(requests),8)
        self.assertEqual([r.method for r in requests[-4:]],['POST','PUT','DELETE','GET'])

if __name__ == '__main__': unittest.main()
