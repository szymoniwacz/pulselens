# Product Context

## Product

- Name: PulseLens.
- Purpose: learn ClickHouse through a working, understandable backend portfolio demo.
- Users: developer/maintainer operating a local demo; recruiter/reviewer inspecting it.
- Primary outcome: HTTP ingestion → ClickHouse persistence → correct filtered analytics → reproducible benchmark.
- Authoritative brief: [issue #1](https://github.com/szymoniwacz/pulselens/issues/1).

## Repository

- Current state: workflow adapter only; no Rails scaffold, product schema, product tests or product CI.
- Proposed stack: Rails API and server-rendered dashboard, PostgreSQL application configuration/authentication, ClickHouse event analytics and RSpec; Docker Compose is confirmed (D-004), as is GitHub Actions CI (D-007).
- Remaining stack/policy proposals await confirmation; the owner delegated versions, ClickHouse library, timeout values and final sorting choice to the relevant future tasks; see [requirements](../docs/project-requirements.md).
- Existing adapter checks: `bash tests/test-adapter.sh`, `bash scripts/check-workflow-leak.sh`.
- Product setup/run/test/lint/build/typecheck commands do not exist yet. Record real commands in the scaffold goal; do not copy stack-profile placeholders.
- Candidate guidance: `.ai/stack-profiles/ruby-rails.md`; not activated by this definition.

## Proposed boundaries — pending readiness confirmation

Rails owns validation, authentication, orchestration and presentation. PostgreSQL owns applications and key digests; ClickHouse owns events and aggregations. No cross-database transaction or background workers. The dashboard uses the shared analytics service with server-selected application context, without API keys in the browser.

## Confirmed operational baseline

A-05–A-09 are approved: deterministic top-event ties, zero-based error indexes, half-open UTC daily buckets and persistent local database volumes; local Linux/macOS, English UI/docs and accessible controls; malformed JSON 400, server-reserved client fields 422, explicit timeout policy and analytics error statuses. MIT, owner-only review/merge, GitHub Actions, no automatic releases, git revert rollback and generator-based local recovery with explicit deletion are confirmed. Details and outstanding choices: [decisions](decisions.md). No implementation is started.

## Current authorization

Definition and backlog preparation only. No implementation or execution automation started. Complete readiness-safe bootstrap before the first product goal. [Roadmap](roadmap.md).
