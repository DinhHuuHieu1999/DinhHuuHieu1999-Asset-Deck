---
title: "Asset Desk MVP proposal"
description: "A scoped equipment inventory product applying the existing base."
document_type: "record"
status: "draft"
audience: ["contributors", "operators"]
---

# Asset Desk MVP proposal

The user selected Asset Desk on 2026-10-25 and approved backend and Flutter source/tests
in this separate repository. Schema scripts are source only; applying migrations,
running database/HTTPS fixtures, deployment and commits require separate approval.
The design follows ToolDeck docs/guides/new-product-recipe.md; that guide
is not bundled as a product runtime dependency.

## Outcome and product boundary

Help an individual find and update records for equipment they own: computers,
phones, network devices and accessories. Asset records are not Toolbox tools,
Projects or background image jobs. No team sharing is included.

Asset Desk is a distinct product concept. Do not silently add another permanent
ToolDeck menu or copy the entire monorepo into a new repository. The selected location is a separate sibling repository using selected base
components, not an optional ToolDeck domain. Independent packaging and committed-base checkout validation are recorded in
the root README; the later Windows runner commit needs its own checkout validation.

## First vertical slice

- Target: Flutter Windows with authenticated backend persistence.
- Flow: open inventory, search/filter, create an asset, edit, refresh and reopen.
- Fields: name (1-120 characters), category (1-64), optional serial (0-120),
  status (`in_use`, `stored`, `repair`, `retired`), notes (0-2000).
- Trim field edges; reject blank required values and over-limit input on server
  and client. Serial is a label, not a credential or a globally unique identifier.
- Duplicate names/serials are allowed; never merge or overwrite records by label.
- Search: case-insensitive literal substring in name, category and serial;
  at most 120 characters. Treat `%` and `_` as ordinary characters.
- Filter: one status, applied server-side before pagination. Apply explicitly;
  reset to page one when applying changed filters.
- List: 50 records per page, updated timestamp descending with ID tie-breaker.
  State any traversal limit explicitly; never imply a truncated list is complete.
- Server supplies UUID, owner, timestamps and optimistic edit version. Read and
  update predicates include the authenticated owner. Unknown/non-owned IDs do
  not reveal another account's record.
- Stale edits preserve the draft and request reload; network/auth errors preserve
  the last successful list with an explicit stale-data message.
- Offline: no new offline database or queued writes. Display failures clearly;
  do not retry a mutation automatically when its outcome is unknown.
- Retain records until an independently approved retention/deletion feature.

## Reuse, not wholesale copying

Reuse established authentication, CSRF/session handling, API transport, database
connection and owner/version patterns. Keep asset DTOs, repository and screens
in their own domain. Flutter must not import TypeScript shared packages.

No new production dependency is planned. Do not carry pilot runtimes, local env,
certificates, credentials, catalog archives or generated builds into the product.
Select an explicit committed base revision and record what is actually reused.

Excluded: delete, images/files, import/export, warranty tracking, loans, QR/NFC,
notifications, AI, workers, microservices, new infrastructure and team roles.

## Acceptance and evidence

Backend typecheck and unit/mock evidence is recorded in the backend README.
The root README records isolated repository, API, recovery and Dart HTTPS evidence.
The operator confirmed the Windows functional flow and keyboard navigation; see
[the native acceptance boundary](windows-native-acceptance-plan.md). The table below
defines required evidence, not a blanket claim that every target check passed.
Native text scaling, screen-reader and error/conflict interactions remain pending.

| Acceptance                                            | Required evidence                               |
| ----------------------------------------------------- | ----------------------------------------------- |
| Discover, add, edit and reopen assets                 | Rendered target review and behavior tests       |
| Input limits and cancellation preserve work           | Boundary and draft-preservation regressions     |
| Search is literal and precedes pagination             | Repository tests with multi-page synthetic data |
| Accounts cannot read/update each other's assets       | Two-owner API and repository tests              |
| Concurrent edits do not overwrite silently            | Version-conflict test preserving client draft   |
| Failure does not imply success or erase prior results | Network/auth/unknown-outcome tests              |
| Records survive restart and restore                   | Separately approved isolated recovery fixture   |
| Existing base domains remain unaffected               | Scoped regression tests                         |
| No model credentials are required                     | Intended startup and non-model flow evidence    |

Capture and inspect a synthetic render before UI implementation. The Asset Desk release candidate built and ran without changing Smart App Control.
A historical ToolDeck v2 Application Control block is not evidence that this
Asset Desk candidate is blocked. Build/test evidence must not be presented as
manual acceptance, and protection must not be disabled to obtain it.

## Execution gates and rollback

1. Product location, backend and Flutter source/tests approved; native functional
   and keyboard checks confirmed, remaining native checks documented separately.
2. Inspect selected base code and runtime contracts; define domain API/schema.
3. Implement source and offline tests without applying a migration to local data.
4. Request separate isolated SQL/HTTPS and native acceptance when needed.
5. Review exact commit scope; request commit and rollout separately.

Rollback disables the new product entry/module and preserves asset data/schema.
No destructive down-migration or cleanup is implicit. Deployment needs verified
backup and an explicit rollback target; this proposal changes no runtime.
