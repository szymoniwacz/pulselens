# Project Decisions

## Confirmed direction — 2026-11-24

Source: owner-authored [issue #1](https://github.com/szymoniwacz/pulselens/issues/1) and explicit definition-only request.

- D-001: PulseLens is an event analytics application for collecting and analyzing application events. Completion requires a clean-checkout journey, correct analytics, CI and repeatable one-million-event measurements.
- D-002: No public hosting, real personal data, queues, user accounts, deduplication or exactly-once promise in the MVP. Preserve unknown-write-outcome warnings and never retry inserts automatically.
- D-003: This stage creates project context and backlog only. It does not authorize implementation, project execution, merge or a readiness declaration.

## Owner confirmations — 2026-11-24

Source: explicit owner reply in the project-definition conversation after PR #12 was opened. These decisions update documentation only; the owner explicitly prohibited starting implementation.

- D-004 (A-07 approved): local Linux/macOS with Docker Compose; English UI/docs; labelled keyboard-usable controls and textual chart equivalents.
- D-005 (A-08 approved with clarification): validate uppercase ISO country codes; reject null/invalid optional values instead of using absent-field defaults. Malformed JSON returns 400. Client-supplied server-reserved fields (application_id, received_at) return 422.
- D-006 (A-09 approved): finite explicit connection/insert/query deadlines; one attempt for writes; analytics invalid filters return 422 and unavailable dependencies return 503. Actual timeout values are delegated, not chosen here.
- D-007: MIT license and GitHub Actions CI confirmed. Recover local demo data with the generator; deleting data requires an explicit command, so no automatic TTL is allowed. No automatic releases for the MVP. Roll back code using git revert. Review and merge remain with the owner; no agent merge is authorized. Retain the existing LICENSE attribution ©2026 Szymon Iwacz; no additional maintenance obligation is introduced.
- D-008: choose and justify compatible versions in scaffold #3; ClickHouse library/transport, actual timeouts and final sorting key in schema/client #5 and analytics #7 as applicable. This delegates bounded technical choices in those future tasks, not implementation now or blanket approval of A-01–A-06.

- D-009 (A-05 approved): top event ties use count DESC/name ASC; validation errors use zero-based event indexes; daily buckets are UTC dates intersecting [from,to), excluding a to date exactly at midnight.
- D-010 (A-06 approved): use persistent local database volumes so ordinary restarts preserve data. Earlier generator recovery, explicit-command-only deletion and no automatic TTL decisions remain in force. Production backup services remain outside MVP scope.

Source for D-009/D-010: explicit owner acceptance of A-05 and A-06 in the project-definition conversation, 2026-11-24. Documentation/PR update only; no implementation or merge authorization.

## Final definition approvals — 2026-11-24

Source: explicit owner acceptance of A-01–A-04 in the project-definition conversation. Update PR #12 and assess remaining start blockers only; do not implement or merge.

- D-011 (A-01 approved): Rails monolith for API/server-rendered dashboard; PostgreSQL for application configuration/authentication; ClickHouse for events/aggregations; RSpec. Compose and GitHub Actions remain approved. Select the ruby-rails guidance profile in requirements.
- D-012 (A-02 approved): name ≤128 UTF-8 bytes, user_id ≤256 bytes, serialized properties JSON ≤16 KiB/event and request body ≤2 MiB; count and byte limits apply together.
- D-013 (A-03 approved): cryptographic key with at least 256 random bits, digest-only SHA-256 storage and indexed digest lookup.
- D-014 (A-04 approved): DateTime64(3, UTC), monthly partitions by occurred_at. Final sorting key stays delegated to #5 under D-008.

## Remaining decisions and readiness

No unapproved A-01–A-09 choice remains. Versions, ClickHouse library, timeout values and final sorting key remain delegated to #3/#5/#7 with rationale required. MergeTree is the source schema proposal for #5 to evaluate, not a newly claimed owner decision. The [requirements](../docs/project-requirements.md#readiness-assessment--2026-11-24) record the readiness-safe bootstrap result and remaining owner review/integration boundary. Definition approval does not complete #2, authorize implementation or permit agent merge.

## Readiness-safe bootstrap handoff — 2026-11-24

The owner explicitly authorized completion of #2 inside PR #12: product README, PulseLens role in AGENTS and readiness validation, stopping before product implementation or merge. No new product or architecture choice is introduced. Branch-level readiness is recorded under the greenfield exception; real application commands and initial service-backed product CI remain owned by #3. Human review/merge and target-branch dependency verification are still pending. Full validation evidence and diff-risk belong to PR #12.

## Scaffold/runtime choices — issue #3

- D-015: Ruby 3.4.13 and Rails 8.1.4.1 are pinned for a reproducible, current-patch scaffold; Rails requires Ruby >=3.2. Use RSpec Rails 8.1.0 for Rails 8.1 request/service specs, pg 1.6.3 for PostgreSQL, Puma 8.0.1 for the local server, Propshaft 1.3.2 for server-rendered CSS, and Rails Omakase 1.1.0 for a small established lint baseline. Gemfile.lock fixes transitive dependencies and platform variants. No Node frontend, queues, background workers or analytics client is added. Package versions were verified against RubyGems metadata; [Ruby release list](https://www.ruby-lang.org/en/downloads/releases/) and [Rails package metadata](https://rubygems.org/api/v2/rubygems/rails/versions/8.1.4.1.json) support the runtime choice.
- D-016: Compose pins PostgreSQL 17.12-bookworm and ClickHouse 26.8.46.6 rather than floating tags. PostgreSQL 17 provides a mature maintained major and its established data-volume path; ClickHouse uses the 26.8 LTS line. Exact tags were checked in the official registries. [PostgreSQL policy](https://www.postgresql.org/support/versioning/) and [ClickHouse Docker documentation](https://clickhouse.com/docs/install/docker). Host ports bind only to loopback; both databases have persistent named volumes and explicitly supplied local passwords. No production deployment or automatic deletion is introduced.
- D-017: /up is Rails process liveness; /ready checks both stores using SELECT 1 and returns 200/503 with safe dependency states. PostgreSQL application connect/pool waits are 2s and server statement timeout 1s. Readiness uses a dedicated short-lived PG connection with a 2s client budget covering DNS resolution, handshake and query; it owns the handle before interruptible communication and always closes it outside the deadline, leaving application-pool connections untouched. ClickHouse HTTP open/read/write limits are 2s each with max_retries=0 and a 2s deadline around the complete request, whose socket closes on interruption. These are bootstrap probes, not the event/analytics client deferred to #5. Credentials come from environment variables; URLs cannot carry credentials, and errors log only dependency/error class.
- D-018: Keep the actual test/lint/autoload/build commands in README and bin/check. Ruby has no static typecheck in this scaffold; Zeitwerk checks autoloading. GitHub Actions runs real Compose services, healthy readiness and controlled outages of each dependency, plus asset compilation, while retaining adapter checks. Product setup does not require private workflow access.

## Event storage choices — issue #5

- D-019: Use the existing Ruby Net::HTTP and JSON libraries and ClickHouse HTTP typed parameter bindings, avoiding a new client dependency. POST only, no ambient proxy, no retries, synchronous JSONEachRow inserts, buffered JSON query results and safe generic errors. Connection limit 2s; whole-query/DDL deadline 15s and whole-insert deadline 30s; server execution limits 13s/28s are best-effort. A lost response may leave the write outcome unknown.
- D-020: MergeTree with monthly UTC partitions and date-first sorting key (application_id, occurred_at, name, event_id), because application/date restrictions are mandatory and name is optional. The real-service EXPLAIN comparison (131,072 synthetic rows per table; CI run 45596923233) selected 1/16 vs 8/16 primary-key granules for the date-only shape and 1/16 vs 1/16 for the name-filtered shape, with equal result counts. See [README](../../README.md#clickhouse-event-storage) for the workload and limitations; these are not latency measurements. No materialized views or deduplication. Separate local development/test databases and idempotent ordered SQL files; no implicit deletion.
