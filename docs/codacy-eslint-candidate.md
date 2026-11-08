# Opt-in ESLint configuration candidate

This configuration is not active. It does not change Codacy MCP registration,
cloud settings, findings acceptance, or the live `.codacy` files.

## Scope

The reviewed snapshot retains 299 rules/options from the installed Codacy ESLint
adapter. Node globals and Jest-family exclusions apply only to three explicit files:
`scripts/client-https-proxy.mjs`, `scripts/client-https-proxy.test.mjs`, and
`scripts/serial-fixture-cleanup.test.mjs`. The last file is an offline `node:test`
fixture-lifecycle regression, not a Jest test.
Other correctness/security rules remain enabled. Backend TypeScript rules work
from either the repository root or backend root. No source is auto-fixed.

The factory requires an explicit path to an existing
`@codacy/tools-eslint-9/package.json` version 0.16.0. It resolves plugins from
that installation, not a hard-coded cache directory. Installed backend Jest
must have major version 30; missing dependencies or unreviewed versions fail.
No dependency is installed by this code.

## Verification

From the repository root, set `CODACY_ESLINT_PACKAGE` to the absolute package JSON
path of the already installed adapter, then run:

```powershell
node --test scripts/codacy-eslint-candidate.test.mjs
```

The environment variable is a process-local locator, not a credential. Tests
require the existing adapter/plugin and backend Jest dependencies. They inspect
effective configurations and lint synthetic snippets, not the repository.

## Integration boundary

`buildCandidate(adapterPackage, repositoryRoot)` returns a flat-config array.
It is not automatically loaded. Any future wrapper must select the intended
root explicitly and pass the result through a separately reviewed integration.
The adapter may ignore an explicit local config path when project ESLint 9
resolves, so that execution branch needs independent verification.

`codacy-eslint-policy.json` is a frozen reviewed snapshot, not automatic sync
with Codacy cloud or subsequent local configuration edits. Re-review the policy
when rules, adapter versions or framework dependencies change. Do not interpret
execution success as findings acceptance or a security PASS.

Before packaging, the local candidate produced the same 305 backend findings
as the recorded six-file scan. Its two-file Node scan retained one security
finding while removing 80 Node/Jest environment-related findings. The packaged version subsequently analyzed all eight files in one local adapter
run without analyzer errors: all 306 findings matched exactly (305 backend,
one Node). Source and live configuration hashes were unchanged. This verifies
execution/parity for those files, not findings acceptance or broader coverage.
No live switch, install, upload, commit or deployment is part of this candidate.

## Opt-in local command

This runner uses the installed ESLint engine directly with the candidate config,
not the MCP adapter's project-config selection branch. It scans only a supplied
manifest (1?100 explicit JS/TS source files, each with its SHA-256). Glob patterns,
external paths, generated/local directories and changed hashes are rejected.
The snapshot remains a reviewed policy, not a live Codacy cloud configuration.

Manifest structure:

```json
{
  "files": [
    {
      "path": "scripts/client-https-proxy.mjs",
      "sha256": "<64 lowercase hex characters>"
    }
  ]
}
```

From the repository root, using an already installed adapter package:

```powershell
node scripts/codacy-eslint-local.mjs . .local/approved-scan.json $env:CODACY_ESLINT_PACKAGE 120
node --test scripts/codacy-eslint-local.test.mjs
```

The last argument is the child-process timeout in seconds (1?900). One process
runs once, without a shell, retries, installation, auto-fix, or upload. JSON on
stdout contains raw ESLint results and a summary. Exit codes: 0 means completed
with no findings in this exact scope; 1 means findings; 2 means incomplete/error,
including timeout, diagnostics, malformed results, fatal parsing, ignored files,
or source/manifest changes. Output is capped at 16 MiB; overflow is incomplete.
No exit code certifies security or unsupported-language coverage. The caller may
redirect stdout to a new ignored local report; output can contain source details.
Do not change source or manifests during analysis. Hash checks detect ordinary
changes, not malicious same-account interference or change-and-revert races.

The runner's 10 offline tests mock analyzer execution. A separately approved
real two-file run completed with 90 findings (89 PostgreSQL fixture findings,
one cleanup-test finding), no fatal errors, and exit code 1. Source hashes
remained unchanged. Counts matched the preceding adapter scan; this is not
full finding-by-finding parity or findings acceptance. The runner is not
connected to default tests, CI or MCP.
