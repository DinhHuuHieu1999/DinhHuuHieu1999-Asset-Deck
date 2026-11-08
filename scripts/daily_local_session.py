"""Exclusive foreground session lock; stale locks require operator review."""

import secrets


class SessionLock:
    """Never overwrite an existing lock or unlink a different session's token."""

    def __init__(self, directory):
        self.path = directory / 'daily-session.lock'
        self.token = secrets.token_hex(32)
        self.held = False

    def acquire(self):
        with self.path.open('x', encoding='utf-8') as stream:
            stream.write(self.token)
        self.held = True

    def release(self):
        if not self.held or self.path.is_symlink():
            raise RuntimeError('Session lock ownership mismatch')
        with self.path.open('r', encoding='utf-8') as stream:
            value = stream.read(65)
        if value != self.token:
            raise RuntimeError('Session lock ownership mismatch')
        self.path.unlink()
        self.held = False
