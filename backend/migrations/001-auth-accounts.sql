-- Run explicitly against the selected PostgreSQL account database, not on app startup.
-- Existing MongoDB ObjectIds are retained so JWT subjects and chat references stay valid.
BEGIN;

CREATE SCHEMA IF NOT EXISTS auth;

CREATE TABLE auth.accounts (
    id text PRIMARY KEY CHECK (id ~ '^[0-9a-f]{24}$'),
    email text NOT NULL UNIQUE CHECK (email = lower(btrim(email))),
    username text NOT NULL UNIQUE CHECK (
        username = lower(btrim(username)) AND length(username) BETWEEN 3 AND 30
    ),
    name text NOT NULL,
    password_hash text NOT NULL,
    role text NOT NULL DEFAULT 'USER' CHECK (role IN ('USER', 'ADMINISTRATOR')),
    status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN (
        'ACTIVE', 'APPROVED', 'ARCHIVED', 'COMPLETED', 'DELETED', 'DRAFT',
        'FAILED', 'INACTIVE', 'PENDING', 'PROCESSING', 'REJECTED', 'SUSPENDED'
    )),
    password_changed_at timestamptz,
    reset_password_token_hash text,
    reset_password_expires_at timestamptz,
    failed_login_attempts integer NOT NULL DEFAULT 0 CHECK (failed_login_attempts >= 0),
    lock_level integer NOT NULL DEFAULT 0 CHECK (lock_level >= 0),
    lock_until timestamptz,
    last_login_at timestamptz,
    require_reverify boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX accounts_status_created_idx ON auth.accounts (status, created_at DESC);
CREATE INDEX accounts_status_updated_idx ON auth.accounts (status, updated_at DESC);
CREATE INDEX accounts_reset_token_idx ON auth.accounts (reset_password_token_hash)
    WHERE reset_password_token_hash IS NOT NULL;

COMMIT;
