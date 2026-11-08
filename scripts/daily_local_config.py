"""Validate non-secret daily runtime configuration before any OS side effects."""

from pathlib import Path


class ConfigError(ValueError):
    """A public validation error that never includes submitted values."""


def validate_config(value, is_file=None, is_dir=None):
    """Return validated absolute paths and loopback ports; never read file contents.

    Private environment injection and TLS validity are separate acceptance gates.
    No arbitrary command, shell argument, or feature override is accepted here.
    """
    files = ('node', 'python', 'backend_supervisor', 'backend_entry',
             'gateway_entry', 'app', 'tls_cert', 'tls_key')
    directories = ('backend_cwd', 'state_dir')
    ports = ('backend_port', 'https_port')
    if type(value) is not dict or set(value) != set(files + directories + ports):
        raise ConfigError('Invalid configuration fields')
    result = {}
    for name in files + directories:
        raw = value[name]
        if not isinstance(raw, str) or not raw or '\x00' in raw:
            raise ConfigError('Invalid runtime path')
        path = Path(raw)
        # Reject traversal before resolving so it cannot be normalized away.
        if not path.is_absolute() or '..' in path.parts:
            raise ConfigError('Runtime paths must be absolute without traversal')
        result[name] = path.resolve()
    file_check = is_file or (lambda path: path.is_file())
    dir_check = is_dir or (lambda path: path.is_dir())
    for name in files:
        if not file_check(result[name]):
            raise ConfigError('Required runtime file is missing')
    for name in directories:
        if not dir_check(result[name]):
            raise ConfigError('Required runtime directory is missing')
    for name in ports:
        port = value[name]
        if type(port) is not int or not 1024 <= port <= 65535:
            raise ConfigError('Invalid loopback port')
        result[name] = port
    if result['backend_port'] == result['https_port']:
        raise ConfigError('Runtime ports must differ')
    if result['tls_key'] == result['tls_cert']:
        raise ConfigError('TLS certificate and key must differ')
    if result['backend_entry'].parent != result['backend_cwd'] / 'dist':
        raise ConfigError('Backend entry must belong to the selected release')
    return result
