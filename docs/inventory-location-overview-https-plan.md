# Location overview HTTPS acceptance

Status: source/offline contracts and one approved HTTPS execution completed;
listed Windows functional checks were separately operator-confirmed.

The existing opt-in `scripts/location-https-fixture.py` now requires overview
source, its compiled backend artifact and the Dart response model before resource
creation. It reuses the owned location lifecycle, existing migrations, default
TLS verification and marker-bound real Dart driver. No new dependency or flag.

The driver checks anonymous refusal, an empty account, all 52 owner assets across
pagination, literal location counts, isolation from the second account, clearing
one location and refusal after sign-out. Success requires the additional exact
boolean `locationOverviewAcceptance`; old or incomplete output fails closed.
The proxy permits only GET on the exact overview path with location opt-in;
query strings reach the backend, which must reject them rather than filter counts.

## Offline checks

```powershell
python -B -m unittest discover -s scripts -p 'test_location_https*.py' -v
node --test scripts/location-overview-proxy.test.mjs
```

A live run requires separate approval for a backend candidate build and one
synthetic PostgreSQL/HTTPS fixture. Do not use an old candidate, disable TLS
verification, read local credentials, change trust/firewall, retry automatically,
or treat offline results as runtime acceptance. Retain owned stopped fixture data.

## Observed HTTPS acceptance

One approved backend build and fixture execution completed without retry.
Fixture `c2bf56657a5f3a8693f8ccb2cf4f557b` accepted the exact Dart result,
including location overview checks and unchanged selected source hashes.
Independent Docker inspection confirmed the container stopped, its database
binding restricted to loopback, and the matching owned volume retained.
No native dialog/UI, deployment or production acceptance is implied.
