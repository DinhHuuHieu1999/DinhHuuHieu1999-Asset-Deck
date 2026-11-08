"""Pure, fail-closed result contract for planned selection HTTPS acceptance.

This module does not start a fixture, import its lifecycle or inspect TLS files.
"""


class AcceptanceRefusal(ValueError):
    """The driver did not provide complete, correctly typed evidence."""


CHECKS = (
    'anonymousDenied',
    'noStore',
    'invalidQueryRejected',
    'ownerIsolation',
    'all51Matches',
    'literalSearch',
    'combinedFilters',
    'emptySelection',
    'scopeAndDatesPreserved',
    'checksumVerified',
    'fullExportUnchanged',
    'noWrites',
    'signedOutDenied',
    'checkBoundaries',
    'v1Unchanged',
)


def validate_result(value):
    """Require every planned check; never promote a partial report to acceptance."""
    expected = {
        'status': 'completed',
        'syntheticOnly': True,
        'selectionExportV2Acceptance': True,
        'owners': 2,
        'assetCount': 51,
        'digest': 'python-sha256-stdin',
        'nativeDialog': 'not-exercised',
        'checks': {name: True for name in CHECKS},
    }
    if not isinstance(value, dict) or value.keys() != expected.keys():
        raise AcceptanceRefusal('Selection HTTPS result incomplete')
    for key, item in expected.items():
        if type(value[key]) is not type(item) or value[key] != item:
            raise AcceptanceRefusal('Selection HTTPS result incomplete')
    checks = value['checks']
    if any(type(checks[name]) is not bool for name in CHECKS):
        raise AcceptanceRefusal('Selection HTTPS checks incorrectly typed')
