# Project Decisions

## Confirmed direction — 2026-11-24

Source: owner-authored [issue #1](https://github.com/szymoniwacz/pulselens/issues/1) and explicit definition-only request.

- D-001: PulseLens is an event analytics application for collecting and analyzing application events. Completion requires a clean-checkout journey, correct analytics, CI and repeatable one-million-event measurements.
- D-002: No public hosting, real personal data, queues, user accounts, deduplication or exactly-once promise in the MVP. Preserve unknown-write-outcome warnings and never retry inserts automatically.
- D-003: This stage creates project context and backlog only. It does not authorize implementation, project execution, merge or a readiness declaration.

## Technical proposals, not confirmed decisions

Issue #1 explicitly calls its technical design a proposal. Rails/PostgreSQL/ClickHouse component details, MergeTree ordering, versions, key digest strategy, field/body limits and local operational policies must not be described as owner-approved decisions yet. Candidate values and confirmation triggers are in [requirements](../docs/project-requirements.md); readiness work owns grouped confirmation. No ADR asserts an unconfirmed choice.
