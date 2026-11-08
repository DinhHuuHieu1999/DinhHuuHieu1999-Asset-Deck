"""Injected daily recovery lifecycle; provisioning stays behind explicit opt-in."""

from daily_local_recovery import verify_base_restore


def accept_recovery(source, target, root, folder, sessions, remaining,
                    verify=verify_base_restore, cleanup_databases=True, checkpoint=None):
    """Seed source over HTTPS, stop writers, restore and authenticate target.

    sessions.open(database) returns a session with seed(), login(asset_id),
    close() and clean() methods. Its close must close the inert app, stop only
    retained owned processes and release its matching lock. clean must return
    literal True only after owned resources and locks have been released.
    Caller must keep source/target distinct, freshly constructed synthetic DBs.
    No retry or deletion is allowed. Any failed cleanup fails the whole run.
    """
    mark = checkpoint or (lambda stage: None)
    active = []
    databases = []
    cleanup_failed = False
    try:
        remaining()
        if source.identity == target.identity:
            raise ValueError('Distinct recovery databases required')
        for role, database in (('source', source), ('target', target)):
            mark(role + '-database-create')
            databases.append(database)
            database.create()
            mark(role + '-database-ready')
            database.wait_ready()
        mark('source-migrate')
        source.migrate(root)
        mark('source-session-open')
        source_session = sessions.open(source)
        active.append(source_session)
        mark('source-seed')
        asset_id = source_session.seed()
        if not isinstance(asset_id, str) or not asset_id:
            raise ValueError('Synthetic asset identity missing')
        mark('source-session-close')
        source_session.close()
        if source_session.clean() is not True:
            raise RuntimeError('Source writers did not stop')
        active.remove(source_session)

        def restored_login(database):
            if database is not target:
                raise ValueError('Restored login target mismatch')
            remaining()
            mark('target-session-open')
            session = sessions.open(target)
            active.append(session)
            mark('target-login-check')
            accepted = session.login(asset_id)
            mark('target-session-close')
            session.close()
            if session.clean() is not True:
                raise RuntimeError('Restored session cleanup incomplete')
            active.remove(session)
            return accepted is True

        options = {'checkpoint': checkpoint} if checkpoint is not None else {}
        return verify(source, target, folder, remaining, restored_login, **options)
    finally:
        # No acceptance restart; only graceful cleanup of retained owned handles.
        for session in reversed(active):
            try:
                session.close()
                if session.clean() is not True:
                    cleanup_failed = True
            except Exception:
                cleanup_failed = True
        for database in reversed(databases) if cleanup_databases and not cleanup_failed else ():
            try:
                database.stop()
            except Exception:
                cleanup_failed = True
        if cleanup_failed:
            raise RuntimeError('Recovery cleanup incomplete; preserve ownership evidence') from None
