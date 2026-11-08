"""Offline-testable lifecycle policy; OS adapters are deliberately not implicit."""

import time


class LifecycleError(Exception):
    """A safe, public lifecycle failure without child-process output."""


class Launcher:
    """Coordinate backend/gateway/app through an explicitly supplied OS adapter.

    The adapter must verify executable identity and process creation identity,
    not merely PID equality. Database provisioning is outside this controller.
    """

    COMPONENTS = ('backend', 'gateway', 'app')

    def __init__(self, adapter, timeout=30, clock=time.monotonic):
        if isinstance(timeout, bool) or not isinstance(timeout, (int, float)):
            raise ValueError('Invalid deadline')
        if not 0 < timeout <= 120:
            raise ValueError('Invalid deadline')
        self.adapter = adapter
        self.timeout = timeout
        self.clock = clock
        self.owned = []

    def _remaining(self, deadline):
        remaining = deadline - self.clock()
        if remaining <= 0:
            raise LifecycleError('Lifecycle deadline exceeded')
        return remaining

    def start(self):
        """Preflight all resources, then start in order; never adopt a listener."""
        if self.owned:
            raise LifecycleError('Session already owns processes')
        deadline = self.clock() + self.timeout
        try:
            self.adapter.preflight(self._remaining(deadline))
            for component in self.COMPONENTS:
                identity = self.adapter.start(component, self._remaining(deadline))
                # Record before readiness so failures still attempt owned cleanup.
                self.owned.append((component, identity))
                self.adapter.ready(component, identity, self._remaining(deadline))
        except Exception:
            try:
                self.stop()
            except LifecycleError:
                raise LifecycleError('Startup failed; owned cleanup requires review') from None
            raise LifecycleError('Startup failed') from None

    def status(self):
        """Return safe labels only; do not expose command lines or environment."""
        return {name: bool(self.adapter.running(name, identity))
                for name, identity in self.owned}

    def stop(self):
        """Stop verified identities in reverse order; retain failures for review."""
        deadline = self.clock() + self.timeout
        failed = []
        for component, identity in reversed(self.owned):
            try:
                if not self.adapter.matches(component, identity):
                    raise LifecycleError('Ownership mismatch')
                self.adapter.stop(component, identity, self._remaining(deadline))
            except Exception:
                failed.append((component, identity))
        self.owned = list(reversed(failed))
        if failed:
            raise LifecycleError('Owned cleanup requires review')
