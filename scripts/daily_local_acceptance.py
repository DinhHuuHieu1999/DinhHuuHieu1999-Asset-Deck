"""Daily runtime acceptance driver; real lifecycle and HTTP adapters are injected."""


def accept_session(launcher, lock, client, close_substitute, remaining, events):
    """Exercise create, graceful stop, restart and read using one owned session.

    The caller must provision only synthetic resources and supply an inert app
    substitute explicitly. No database/container operation is hidden here.
    """
    clean = False
    lock.acquire()
    try:
        launcher.timeout = min(30, remaining())
        launcher.start()
        events('first-start')
        asset_id = client.create_synthetic_asset()
        client.assert_invalid_requests_rejected()
        close_substitute()
        launcher.timeout = min(30, remaining())
        launcher.stop()
        if launcher.owned:
            raise RuntimeError('Owned processes remain after stop')
        events('first-stop')
        launcher.timeout = min(30, remaining())
        launcher.start()
        client.login_and_assert_asset(asset_id)
        events('restart-persistence')
        close_substitute()
        launcher.timeout = min(30, remaining())
        launcher.stop()
        if launcher.owned:
            raise RuntimeError('Owned processes remain after restart')
        clean = True
    finally:
        if not clean:
            # Cleanup receives a separate bounded allowance; never retries acceptance.
            launcher.timeout = 30
            try:
                close_substitute()
            finally:
                launcher.stop()
        if not launcher.owned:
            lock.release()
    return {'status': 'completed', 'syntheticOnly': True, 'restartPersistence': True,
            'nativeAcceptance': 'not-tested-inert-substitute', 'backupAcceptance': 'pending'}
