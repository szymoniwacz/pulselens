# Product Context

## Product

- Name: PulseLens.
- Purpose: learn ClickHouse through a working, understandable backend portfolio demo.
- Users: developer/maintainer operating a local demo; recruiter/reviewer inspecting it.
- Primary outcome: HTTP ingestion → ClickHouse persistence → correct filtered analytics → reproducible benchmark.
- Authoritative brief: [issue #1](https://github.com/szymoniwacz/pulselens/issues/1).

## Repository

- Current state: Rails scaffold with /up and /ready, local Compose dependencies, RSpec and service-backed product CI. Versioned event schema and bounded internal ClickHouse client are integrated. Application persistence, operator key creation and reusable Bearer authentication are integrated. Shared exact analytics and GET /api/v1/analytics are integrated. The deterministic synthetic event generator is integrated. Authenticated synchronous HTTP ingestion is integrated. #8 adds the local server-rendered dashboard; the full benchmark remains planned.
- Approved stack: Rails API and server-rendered dashboard, PostgreSQL application configuration/authentication, ClickHouse event analytics and RSpec; Docker Compose is confirmed (D-004), as is GitHub Actions CI (D-007).
- All A-01–A-09 policies are approved; the owner delegated versions, ClickHouse library, timeout values and final sorting choice to the relevant future tasks; see [requirements](../docs/project-requirements.md).
- Existing adapter checks: `bash tests/test-adapter.sh`, `bash scripts/check-workflow-leak.sh`.
- Real commands are recorded in README: bin/setup, bin/dev, bin/check, bundle exec rspec/rubocop, Rails zeitwerk:check and assets:precompile. No static typechecker; use the Ruby version in .ruby-version.
- Active guidance: `.ai/stack-profiles/ruby-rails.md`, selected after A-01 approval.

## Approved boundaries

Rails owns validation, authentication, orchestration and presentation. PostgreSQL owns applications and key digests; ClickHouse owns events and aggregations. No cross-database transaction or background workers. The dashboard uses the shared analytics service with server-selected application context, without API keys in the browser.

## Confirmed operational baseline

A-01–A-09 are approved (D-004–D-014): Rails/PG/ClickHouse/RSpec, input byte limits, digest-only key design, UTC millisecond timestamps and monthly partitions; deterministic top-event ties, zero-based error indexes, half-open UTC daily buckets and persistent local database volumes; local Linux/macOS, English UI/docs and accessible controls; malformed JSON 400, server-reserved client fields 422, explicit timeout policy and analytics error statuses. MIT, owner-only review/merge, GitHub Actions, no automatic releases, git revert rollback and generator-based local recovery with explicit deletion are confirmed. Details and remaining future-task choices: [decisions](decisions.md). Event storage choices are recorded in D-019–D-020; #5 does not implement HTTP ingestion or analytics.

## Current authorization

PR #12 merged to main at 1081c21; #2 is complete and dependency preflight for scaffold #3 passed. PR #13 merged to main at f7de086; #3 is closed. PR #15 merged at 1ce3698; #5 is closed. PR #16 merged at 61e43b0; #4 is closed. PR #17 merged at 9649b93; #7 is closed. PR #18 merged at 7ffa7ef; #9 is closed and its million-event CI evidence is recorded (run 45628527347); local reproduction remains pending. PR #19 merged at 547cdef; #6 is closed, including the HTTP ingestion example. Issue #8 is authorized for implementation; validation, manual browser inspection and owner review remain required. [Roadmap](roadmap.md).
