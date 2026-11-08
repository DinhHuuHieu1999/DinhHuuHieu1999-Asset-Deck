"""Retained-handle child ownership, without PID lookup or tree termination."""

import secrets
import subprocess
import time


class ProcessError(RuntimeError):
    """Public process failure without command lines, environment, or output."""


class OwnedProcesses:
    """Keep the original Popen objects until shutdown is confirmed.

    On Windows Popen retains the process handle. This controller never opens a
    replacement process by PID. It intentionally cannot adopt a detached session.
    Graceful shutdown must be implemented by the application's control adapter.
    """

    def __init__(self, spawn=subprocess.Popen, token=secrets.token_hex, clock=time.monotonic):
        self.spawn = spawn
        self.token = token
        self.children = {}
        self.clock = clock

    def start(self, name, argv, cwd, environment):
        """Spawn an exact argv with inherited secrets only in child environment."""
        if name not in ('backend', 'gateway', 'app') or name in self.children:
            raise ProcessError('Invalid child lifecycle')
        identity = self.token(32)
        try:
            child = self.spawn(list(argv), cwd=str(cwd), env=dict(environment),
                               shell=False, stdin=subprocess.PIPE,
                               stdout=(subprocess.DEVNULL if name == 'app' else subprocess.PIPE),
                               stderr=subprocess.DEVNULL,
                               creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        except Exception:
            raise ProcessError('Child start failed') from None
        self.children[name] = (identity, child)
        return identity

    def matches(self, name, identity):
        """Verify an in-memory session token, never a caller-supplied PID."""
        item = self.children.get(name)
        return item is not None and secrets.compare_digest(item[0], identity)

    def running(self, name, identity):
        """Check liveness through the originally retained handle."""
        if not self.matches(name, identity):
            raise ProcessError('Child ownership mismatch')
        return self.children[name][1].poll() is None

    def stop(self, name, identity, timeout, request_shutdown):
        """Request graceful exit and wait; never force-kill on timeout."""
        if not self.matches(name, identity):
            raise ProcessError('Child ownership mismatch')
        child = self.children[name][1]
        try:
            if child.poll() is None:
                deadline = self.clock() + timeout
                request_shutdown(child, timeout)
                remaining = deadline - self.clock()
                if remaining <= 0:
                    raise TimeoutError('Shutdown deadline exceeded')
                child.wait(timeout=remaining)
        except Exception:
            # Preserve the original handle/token for a later explicit review.
            raise ProcessError('Graceful child shutdown incomplete') from None
        if child.stdin is not None:
            child.stdin.close()
        del self.children[name]
