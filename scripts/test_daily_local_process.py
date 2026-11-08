"""Retained-handle process tests with fake Popen only."""

import io
import unittest
from daily_local_process import OwnedProcesses, ProcessError


class Child:
    def __init__(self):
        self.stdin = io.BytesIO()
        self.exit_code = None

    def poll(self):
        return self.exit_code

    def wait(self, timeout):
        if self.exit_code is None:
            raise TimeoutError('private command line')
        return self.exit_code


class ProcessTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        self.child = Child()
        def spawn(*args, **kwargs):
            self.calls.append((args, kwargs))
            return self.child
        self.processes = OwnedProcesses(spawn, lambda size: 'session-token')

    def start(self):
        return self.processes.start('backend', ['node', 'main.js'], '.',
                                    {'PRIVATE_SECRET': 'not-an-argument'})

    def test_no_shell_or_secret_arguments(self):
        token = self.start()
        self.assertTrue(self.processes.running('backend', token))
        args, kwargs = self.calls[0]
        self.assertFalse(kwargs['shell'])
        self.assertNotIn('not-an-argument', str(args))

    def test_wrong_identity_never_requests_shutdown(self):
        self.start()
        with self.assertRaises(ProcessError):
            self.processes.stop('backend', 'wrong', 1,
                                lambda *args: self.fail('shutdown requested'))
        self.assertIn('backend', self.processes.children)

    def test_graceful_shutdown_releases_handle(self):
        token = self.start()
        def shutdown(child, timeout):
            child.exit_code = 0
        self.processes.stop('backend', token, 1, shutdown)
        self.assertEqual(self.processes.children, {})
        self.assertTrue(self.child.stdin.closed)

    def test_timeout_preserves_handle_no_force_kill(self):
        token = self.start()
        with self.assertRaisesRegex(ProcessError, '^Graceful child shutdown incomplete$'):
            self.processes.stop('backend', token, 1, lambda *args: None)
        self.assertTrue(self.processes.matches('backend', token))

    def test_already_exited_does_not_signal(self):
        token = self.start()
        self.child.exit_code = 0
        self.processes.stop('backend', token, 1,
                            lambda *args: self.fail('signal to exited child'))
        self.assertEqual(self.processes.children, {})

    def test_duplicate_start_refused(self):
        self.start()
        with self.assertRaises(ProcessError):
            self.start()
        self.assertEqual(len(self.calls), 1)


if __name__ == '__main__':
    unittest.main()
