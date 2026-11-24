# Project Decisions

## Confirmed direction — 2026-11-24

Source: owner-authored [issue #1](https://github.com/szymoniwacz/pulselens/issues/1) and explicit definition-only request.

- D-001: PulseLens is a small local synthetic event-analytics portfolio demo for learning ClickHouse and discussing backend design. Completion requires a clean-checkout journey, correct analytics, CI and repeatable one-million-event measurements.
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

## Remaining proposals

A-01 is partially approved (GitHub Actions and Docker Compose); Rails monolith, PostgreSQL/ClickHouse responsibilities and RSpec remain proposed. A-02/A-03 are unapproved. A-04 retains proposed precision/partitions while sorting selection is delegated. See the [proposal approval register](../docs/project-requirements.md#proposal-approval-register) for values and return triggers. A-05–A-09 are approved and must not be requested again as if unapproved. No readiness declaration or implementation follows from these confirmations.
