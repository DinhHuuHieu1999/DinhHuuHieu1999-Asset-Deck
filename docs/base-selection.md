# Base selection

## Pinned origin

ToolDeck commit: `79e22d0fca9281710c782a9abe7ab151d76b6ef4`.
Only committed source from this revision may be selected for the first baseline.
The MVP document is a new design, not a file claimed to exist at that revision.

## Selected boundaries

- Backend auth, CSRF, database connection and session contracts require an import
  closure review before extraction; the existing app manifest has workspace
  dependencies and unrelated optional domains. Copying it alone is insufficient.
- Flutter API transport/session behavior is reusable; asset models and screens
  must remain product-owned. Do not copy ToolDeck domain navigation wholesale.
- Projects provides owner-scoped persistence and optimistic-version examples;
  checklist/export/recovery features are not asset requirements.
- Preserve applicable notices/licenses for any source actually copied. Do not
  assume an independently distributable license: the current backend manifest is
  marked UNLICENSED. Local user-owned development is not publication approval.

## Exclusions and gates

Selected backend source/tests and account schema were copied from the pinned
revision, with relative imports and explicit product adaptations recorded in
[source provenance](source-provenance.json). A product-owned assets domain,
PostgreSQL-only composition and exact-version package manifest were added.
Only an empty app-owned env template is included. No source Git history,
remote, hooks, real env, secrets, certificates, database, uploads, dependencies,
builds or pilot runtime were transferred.

The manifest reuses existing base dependency versions; TypeScript resolves to
6.0.3 from the pinned base lockfile catalog. No new library is introduced.
This is not an independent transitive lockfile or permission to install packages.
Flutter extraction and independent dependency resolution remain pending.
No services, migrations or native launch are authorized by this document.

## Verified coupling at the pinned revision

A static inventory of auth, CSRF and database module imports reaches 35 backend
TypeScript files, with no unresolved local imports in that inventory. See
[import inventory](base-import-inventory.json) for exact origin blob hashes.
This is not a compiler or complete runtime dependency closure. External packages,
workspace package internals, dynamic imports and test prerequisites need review.

| Origin boundary                             | Decision for extraction                                                                                             |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `app/modules/routes.module.ts`              | Replace composition; exclude social/network/files/Projects/Toolbox routes.                                          |
| `app/modules/app.module.ts`                 | Adapt composition; preserve relevant guards/CSRF, do not silently drop protections.                                 |
| `domains/auth/auth.module.ts`               | Adapt for PostgreSQL-only storage; do not retain unused Mongo composition.                                          |
| `app/modules/database.module.ts`            | Adapt PostgreSQL wiring; never fall back to MongoDB on missing configuration.                                       |
| `domains/auth/auth.service.ts`              | Retain security behavior and its regression coverage; cache and administrative/reset paths need explicit decisions. |
| `infrastructure/strategies/jwt.strategy.ts` | Retain account-active/reverification checks, not just token signature verification.                                 |
| Flutter `lib/api/tooldeck_api.dart`         | Extract transport/session behavior with its tests; remove unrelated domain/import state only after coverage review. |
| Flutter `pubspec.yaml`                      | Existing client uses Flutter SDK only at runtime; do not introduce a transport package by default.                  |

The 35-file inventory still includes Mongo adapters and DTOs through auth imports;
therefore it must not be used directly as an extraction allowlist. The next source
phase needs product-specific composition and a reviewed manifest/dependency set.
The actual extraction excludes Mongo adapters and gRPC. One inherited repository
regression originally imported gRPC; only those gRPC-specific assertions were
removed, retaining its HTTP/JWT checks. Dependencies were subsequently installed in the product with lifecycle scripts
disabled; its independent lockfile records the resolved dependency graph.
PostgreSQL pool application name and its test now identify Asset Desk.
