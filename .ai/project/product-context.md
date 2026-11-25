# Product Context

## Product

- Name: PulseLens.
- Purpose: collect application events and provide accurate, filterable analytics.
- Users: application operators, API integrators and maintainers.
- Primary outcome: HTTP ingestion → ClickHouse persistence → correct filtered analytics → reproducible benchmark.
- Authoritative brief: [issue #1](https://github.com/szymoniwacz/pulselens/issues/1).

## Repository

- Current state: Rails scaffold with /up and /ready, local Compose dependencies, RSpec and service-backed product CI. No domain applications/auth, event schema/client, ingestion, analytics or dashboard yet.
- Approved stack: Rails API and server-rendered dashboard, PostgreSQL application configuration/authentication, ClickHouse event analytics and RSpec; Docker Compose is confirmed (D-004), as is GitHub Actions CI (D-007).
- All A-01–A-09 policies are approved; the owner delegated versions, ClickHouse library, timeout values and final sorting choice to the relevant future tasks; see [requirements](../docs/project-requirements.md).
- Existing adapter checks: `bash tests/test-adapter.sh`, `bash scripts/check-workflow-leak.sh`.
- Real commands are recorded in README: bin/setup, bin/dev, bin/check, bundle exec rspec/rubocop, Rails zeitwerk:check and assets:precompile. No static typechecker; use the Ruby version in .ruby-version.
- Active guidance: `.ai/stack-profiles/ruby-rails.md`, selected after A-01 approval.

## Approved boundaries

Rails owns validation, authentication, orchestration and presentation. PostgreSQL owns applications and key digests; ClickHouse owns events and aggregations. No cross-database transaction or background workers. The dashboard uses the shared analytics service with server-selected application context, without API keys in the browser.

## Confirmed operational baseline

A-01–A-09 are approved (D-004–D-014): Rails/PG/ClickHouse/RSpec, input byte limits, digest-only key design, UTC millisecond timestamps and monthly partitions; deterministic top-event ties, zero-based error indexes, half-open UTC daily buckets and persistent local database volumes; local Linux/macOS, English UI/docs and accessible controls; malformed JSON 400, server-reserved client fields 422, explicit timeout policy and analytics error statuses. MIT, owner-only review/merge, GitHub Actions, no automatic releases, git revert rollback and generator-based local recovery with explicit deletion are confirmed. Details and remaining future-task choices: [decisions](decisions.md). Scaffold implementation is scoped to #3.

## Current authorization

PR #12 merged to main at 1081c21; #2 is complete and dependency preflight for scaffold #3 passed. The owner authorized #3 through a review-ready PR without merge. #3 adds only scaffold/infrastructure, operational probes, tests and commands. [Roadmap](roadmap.md).
