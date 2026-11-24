# Scope

## Current authorized work

Issue #3 is authorized through implementation, validation and a review-ready PR, without merge. Definition/readiness from #1/#2 is integrated by PR #12. In this goal, add Rails scaffold, local database dependencies/configuration, process/dependency health, actual setup/run/test/lint/build commands, initial service-backed CI and directly related documentation. Domain applications/authentication, event schema/client, ingestion, analytics and dashboard remain outside #3.

## MVP delivery scope after readiness and execution authorization

- Application creation command, one-time cryptographic API key display and digest-only storage.
- Authenticated synchronous batch ingestion, 1–1000 events, whole-batch validation before a single ClickHouse insert.
- Versioned event schema and client, explicit timeouts and failure visibility.
- Authenticated per-application analytics over UTC half-open ranges up to 90 days; exact unique users, daily series and top names.
- Local server-rendered dashboard sharing analytics logic, without browser-held API keys.
- Bounded-memory deterministic synthetic generator for at least two applications and one million events.
- Feature tests, real ClickHouse integration, service-backed CI, README and reproducible benchmark.

Detailed contracts: [requirements](../docs/project-requirements.md). Sequence and prerequisites: [roadmap](roadmap.md).

## Out of scope

User accounts/roles; public hosting; queues/workers or asynchronous ingestion; deduplication or exactly-once guarantees; retention analytics, funnels/cohorts; revenue/currency analytics; materialized views; Kafka; separate frontend; real analytics providers or personal data.

Local demo data recovery via the generator and deletion only by explicit command are confirmed (D-007). The explicit-deletion rule excludes automatic TTL. Persistent local database volumes preserving data across ordinary restarts are confirmed (D-010); production backup services are outside the local MVP. No automatic deletion is authorized.

## Scope changes

New material product, security or architecture choices require owner confirmation. A-01–A-09 are confirmed in D-004–D-014. Versions, ClickHouse library, timeout values and sorting-key selection are delegated to the relevant tasks; other source proposals must be evaluated there, not silently promoted to owner-approved choices.
