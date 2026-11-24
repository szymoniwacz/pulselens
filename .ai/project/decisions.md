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

## Remaining proposals

A-01 is partially approved (GitHub Actions and Docker Compose). A-02/A-03/A-05 are unapproved. A-04 retains proposed precision/partitions while sorting selection is delegated. A-06 is partially approved (generator recovery, explicit deletion and no automatic TTL); the persistent-volume proposal remains unapproved. Production backup services are outside the local MVP. See the [proposal approval register](../docs/project-requirements.md#proposal-approval-register) for values and return triggers. A-07–A-09 must not be requested again as if unapproved. No readiness declaration or implementation follows from these confirmations.
