"""Source-only Windows runner contracts; no compiler or executable is invoked."""
import hashlib
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


class RunnerTests(unittest.TestCase):
    def test_rendered_templates_match_recorded_source_selection(self):
        manifest = json.loads((ROOT / 'docs/windows-runner-provenance.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest['sdkVersion'], '3.47.4')
        self.assertEqual(len(manifest['files']), 15)
        for item in (manifest['files'] + manifest['pluginMetadata']['files']
                     + manifest.get('inventoryExport', {}).get('files', [])):
            path = ROOT / item['destination']
            self.assertTrue(path.is_file(), item['destination'])
            data = path.read_bytes()
            if item['destinationHashMode'] == 'utf8-lf':
                data = data.replace(b'\r\n', b'\n')
            self.assertEqual(hashlib.sha256(data).hexdigest(), item['destinationSha256'])
            if path.suffix != '.ico':
                self.assertNotIn('{{', data.decode('utf-8').replace('//{{NO_DEPENDENCIES}}', ''))

    def test_name_icon_and_license_are_self_contained(self):
        windows = ROOT / 'flutter/windows'
        self.assertIn('set(BINARY_NAME "asset_desk")', (windows / 'CMakeLists.txt').read_text())
        self.assertIn('L"asset_desk"', (windows / 'runner/main.cpp').read_text())
        self.assertIn('resources\\\\app_icon.ico', (windows / 'runner/Runner.rc').read_text())
        self.assertEqual((windows / 'runner/resources/app_icon.ico').read_bytes()[:4], b'\x00\x00\x01\x00')
        self.assertIn('Redistribution and use', (windows / 'FLUTTER-LICENSE').read_text())

    def test_cmake_plugin_inputs_exist_even_without_a_pub_step(self):
        windows = ROOT / 'flutter/windows'
        for name in ('generated_plugins.cmake', 'generated_plugin_registrant.cc',
                     'generated_plugin_registrant.h'):
            self.assertTrue((windows / 'flutter' / name).is_file(), name)
        plugins = (windows / 'flutter/generated_plugins.cmake').read_text()
        self.assertIn('list(APPEND FLUTTER_PLUGIN_LIST\n)', plugins)
        self.assertIn('list(APPEND FLUTTER_FFI_PLUGIN_LIST\n)', plugins)
        registrant = (windows / 'flutter/generated_plugin_registrant.cc').read_text()
        self.assertNotIn('RegisterWithRegistrar', registrant)


if __name__ == '__main__':
    unittest.main()
