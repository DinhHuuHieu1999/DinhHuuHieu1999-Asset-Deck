"""Configuration contract tests with injected filesystem predicates only."""

from pathlib import Path
import unittest

from daily_local_config import ConfigError, validate_config


class ConfigTests(unittest.TestCase):
    def setUp(self):
        root = Path.cwd().resolve() / 'synthetic-not-created'
        self.value = {name: str(root / name) for name in (
            'node', 'python', 'backend_supervisor', 'gateway_entry',
            'app', 'tls_cert', 'tls_key', 'state_dir')}
        self.value.update(backend_cwd=str(root / 'backend'),
                          backend_entry=str(root / 'backend' / 'dist' / 'main.js'),
                          backend_port=29445, https_port=29443)

    def validate(self):
        return validate_config(self.value, lambda path: True, lambda path: True)

    def test_valid_without_filesystem_reads(self):
        self.assertEqual(self.validate()['https_port'], 29443)

    def test_unknown_fields_and_secret_values_not_echoed(self):
        self.value['password'] = 'private-secret'
        with self.assertRaisesRegex(ConfigError, '^Invalid configuration fields$'):
            self.validate()

    def test_each_missing_field(self):
        original = dict(self.value)
        for name in original:
            self.value = dict(original)
            del self.value[name]
            with self.assertRaises(ConfigError):
                self.validate()

    def test_invalid_ports(self):
        for port in (True, 0, 1023, 65536, '29443', 29445):
            self.value['https_port'] = port
            with self.assertRaises(ConfigError):
                self.validate()

    def test_relative_and_traversal_paths(self):
        for raw in ('relative', str(Path.cwd() / '..' / 'secret'), 'bad\x00path'):
            self.value['tls_key'] = raw
            with self.assertRaises(ConfigError):
                self.validate()

    def test_missing_artifacts(self):
        with self.assertRaisesRegex(ConfigError, 'file is missing'):
            validate_config(self.value, lambda path: False, lambda path: True)
        with self.assertRaisesRegex(ConfigError, 'directory is missing'):
            validate_config(self.value, lambda path: True, lambda path: False)

    def test_backend_release_boundary(self):
        self.value['backend_entry'] = self.value['app']
        with self.assertRaisesRegex(ConfigError, 'selected release'):
            self.validate()

    def test_distinct_tls_material(self):
        self.value['tls_key'] = self.value['tls_cert']
        with self.assertRaises(ConfigError):
            self.validate()


if __name__ == '__main__':
    unittest.main()
