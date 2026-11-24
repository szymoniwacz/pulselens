# Project Requirements

Revision: definition-1, 2026-11-24. Source: [issue #1](https://github.com/szymoniwacz/pulselens/issues/1), no comments at definition time. Backlog: [roadmap](../project/roadmap.md).

## Project summary

PulseLens is an event analytics application for collecting and exploring application events. The current version supports local operation with synthetic data.

The source establishes product intent and requested behavior; it explicitly labels technical design as a proposal. Below, functional requirements preserve the requested MVP contract. Proposed implementation details and additional defaults are not approved architecture. Confirm them during readiness before product implementation.

## Users

| User | Needs | Notes |
|---|---|---|
| Developer/maintainer | Operate the demo, understand storage/query trade-offs | Local synthetic data only |
| API integrator/maintainer | Reproduce behavior, inspect tests and measurements | No public hosting or login required |

## Problems to solve

- Demonstrate a complete event ingestion and analysis flow with understandable boundaries.
- Prevent misleading analytics, cross-application leakage and unsupported performance claims.

## Goals and success criteria

The clean-checkout README journey creates a key, ingests events over HTTP, generates synthetic data and displays correct dashboard analytics. Service-backed tests pass in CI. One-million-event measurements include exact queries, environment and repeatable procedure. No arbitrary CI latency threshold or PostgreSQL superiority claim.

## Non-goals

See [scope](../project/scope.md): no accounts/roles, public deployment, queues/workers, deduplication/exactly-once, retention analytics, funnels/cohorts, revenue/currency analytics, materialized views, Kafka, separate frontend, real provider integrations or personal data.

## Core workflows

1. Start local dependencies and app following the eventual README; create an application and display its random key once.
2. Send Bearer-authenticated events; validate the complete batch before one confirmed insert; distinguish rejection from unknown write outcome.
3. Read application-scoped analytics via API or server-rendered dashboard using identical query logic and filters.
4. Generate a reproducible multi-application dataset in bounded memory, then run and report benchmark queries.

## Functional requirements

All rows are must-have MVP outcomes from issue #1. Technical representations remain proposals where marked.

| ID | Requirement | Verification |
|---|---|---|
| FR-001 | Command creates application with UUID, name, key digest and timestamps; cryptographically random key shown once, digest only stored; Bearer auth; no key logging | Creation, persistence and authentication specs; log inspection |
| FR-002 | Events contain authenticated application_id, client event_id UUID, required name/user_id, occurred_at and server received_at, platform/country and object properties; versioned ClickHouse setup | Schema and real-database round trip |
| FR-003 | POST /api/v1/events accepts 1–1000 events; validates all before one batch insert; never trusts body application_id or received_at; no automatic insert retry | Request specs plus real ClickHouse; prove invalid batch writes nothing |
| FR-004 | Missing platform/country → unknown; missing properties → {}; timestamp timezone required, normalize UTC; explicit field/properties/body limits; errors identify index and field | Boundary and normalization specs |
| FR-005 | Ingestion: 201 only after confirmed insert with accepted count; 401 missing/invalid key; 413 oversized body; 422 invalid batch; 503 ClickHouse unavailable | HTTP contract and dependency-failure specs |
| FR-006 | GET /api/v1/analytics uses Bearer key; required from/to, from < to, at most 90 days, UTC [from,to); optional name/platform/country combine with AND; safe binding and application scope in every query | Filter, injection, isolation and timestamp boundary tests |
| FR-007 | ClickHouse computes total events, exact range unique users, daily events and exact daily users, top 10 names; deterministic ties, zero days, zero empty counters and empty top list | Known fixture comparisons; repeated users across days; partial-day/empty ranges |
| FR-008 | Local single-page dashboard: server-side application selection, dates and dimension filters, counters, daily chart, top table, empty/error states; same analytics service; no keys sent to browser | System/request checks; API/dashboard parity; rendered output inspection |
| FR-009 | Generator accepts event count, date range and seed; at least two applications, returning users, multiple names/platforms/countries, reproducible nonuniform activity; bounded-memory batches; supports 1 million events; no implicit deletion | Fixed-seed equality, count/distribution checks, multi-batch test and full demo run |
| FR-010 | Environment config and secret-free example; explicit connection/query timeouts; versioned schema; documented rebuild; separate liveness and dependency readiness; useful secret-free errors | Fresh setup, unavailable dependency checks and rebuild documentation |
| FR-011 | Tests ship with features; RSpec and real ClickHouse integration proposed; CI runs required services and meaningful checks without latency gates | Feature evidence plus cross-system coverage matrix and green CI |
| FR-012 | README covers purpose, architecture, clean setup, key creation, curl, generator, tests, store rationale, schema/query decisions and limitations | Clean-checkout walkthrough |
| FR-013 | Benchmark uses 1 million events, records application count/date range/seed, versions/environment, exact queries/procedure; first vs subsequent executions, time and rows/bytes read where available | Recorded results and independent repeat run; no unsupported comparison |

## Data and inputs

| Input | Source | Format and constraints |
|---|---|---|
| Application name | Local operator command | Proposed PostgreSQL Application(id UUID, name, api_key_digest, created_at, updated_at) |
| Batch | HTTP client | JSON object with events array; synthetic identifiers only |
| event_id, name, user_id | Client | UUID, required string, required synthetic string |
| occurred_at | Client | Timestamp with timezone; normalized UTC |
| application_id, received_at | Server | Authenticated application UUID, assigned UTC time |
| platform | Client | web/ios/android/unknown proposal; absent defaults unknown |
| country | Client | Two-letter code or unknown; absent defaults unknown; validation policy open |
| properties | Client | JSON object; absent defaults {}; proposed storage as String |
| Analytics filters | API/dashboard | from, to; optional name/platform/country |
| Generator parameters | Local operator | Count, explicit date range, random seed |

## Outputs

| Output | Consumer | Contract |
|---|---|---|
| Key | Operator | Full key once; never persisted in clear or logged |
| Ingest response | Client | Status contracts in FR-005; no transactional/exactly-once claim |
| Analytics | API/dashboard | FR-006–007; bounded UTC range and application isolation |
| Dashboard | Local reviewer | FR-008; keys stay server-side |
| Benchmark report | Reviewer | FR-013; measurement evidence, no speed target invented |

## Integrations and technical preferences

Proposed architecture: synchronous Rails API/dashboard → PostgreSQL for applications/key digests; ClickHouse for events/aggregations. Docker Compose for local dependencies, RSpec and GitHub Actions for validation. No queues or cross-store transactions. Keep analytics SQL/service shared between API and dashboard. PostgreSQL failure must fail authentication safely; do not mistake process liveness for database readiness.

Proposed event schema: MergeTree, monthly occurred_at partitions; UUID application_id/event_id, String name/user_id/properties, DateTime64 UTC timestamps, LowCardinality(String) platform/country. DateTime64 precision is not specified. Candidate ORDER BY (application_id, name, occurred_at, event_id) must be compared against application+date queries without name filters as well as name-filtered queries before final selection. No materialized view needed to resolve this trade-off.

ClickHouse inserts have no automatic retries, including client-level retries. A timeout/lost response can mean an unknown write outcome. Pre-validation does not promise transactional all-or-nothing storage under server failures. event_id does not deduplicate repeat submissions; counters may increase.

## Constraints and quality requirements

- Small local demo, synthetic data only; no public exposure of unauthenticated dashboard.
- Aggregate in ClickHouse; Rails may fill missing dates from aggregated results.
- Range uniques are exact across the full range, never a sum of daily uniques.
- Every analytics query must include authenticated application scope and use safe binding.
- Cover each individual and combined filter, UTC grouping/offset normalization, [from,to) boundaries, two-application isolation, empty data/missing days, keys, invalid batches, limits and dependency failure.
- Real ClickHouse integration is required; mocks alone do not prove SQL or storage behavior.
- Numeric throughput/latency, budget and supported runtime versions are unspecified. Measure before claiming performance.

## Active stack profile

None selected yet. Candidate: `.ai/stack-profiles/ruby-rails.md`; activate after owner confirmation in readiness work. Its example commands are placeholders. Current real checks cover the workflow adapter only: `bash tests/test-adapter.sh` and `bash scripts/check-workflow-leak.sh`. Real application commands and product CI are deferred to the scaffold-producing goal under the greenfield bootstrap exception.

## Security and privacy requirements

Only synthetic user identifiers and properties. Store digests only; never log keys or echo them through errors, URLs, rendered dashboard or browser requests. Application scope derives from authentication, never client fields. Dashboard application selection is a trusted local-only surface, not public multi-user authorization. Any public deployment requires a separate security decision and is excluded.

## Assumptions and candidate defaults

These proposals are not requirements or accepted defaults. Readiness work confirms them or records alternatives before product work.

| ID | Candidate | Why it matters | Confirm by |
|---|---|---|---|
| A-01 | Rails monolith, PostgreSQL + ClickHouse, Compose, RSpec, GitHub Actions | Source stack is explicitly proposed; versions/client library not chosen | Readiness owner confirmation; pin compatible versions in scaffold |
| A-02 | name ≤128 UTF-8 bytes, user_id ≤256 bytes, properties serialized JSON ≤16 KiB/event, body ≤2 MiB | Concrete bounded input without promising all 1000 events fit when individually large | Readiness; ingestion specifies transport/body enforcement and boundary specs |
| A-03 | SHA-256 digest of at least 256 random key bits, indexed digest lookup | Key entropy and lookup strategy must support one-time display/digest-only storage | Readiness security confirmation before authentication work |
| A-04 | DateTime64(3, UTC); monthly partitions; compare proposed name-first order to time-first order after application_id | Precision and sort affect timestamp boundaries and scan work | Readiness approves evaluation boundary; schema goal records selected layout with representative queries |
| A-05 | Top ties: count DESC, name ASC; zero-based error indexes; daily buckets are UTC dates intersecting [from,to) | Makes ties/errors/partial-day ranges testable; excludes an exact-midnight to day | Readiness contract confirmation before ingestion/analytics |
| A-06 | No automatic TTL; local volumes survive ordinary restart; explicit reset only; no production backup service | Source excludes retention analytics but does not specify storage lifecycle | Readiness owner confirmation before persistence |
| A-07 | Local desktop Linux/macOS with Docker Compose; English UI/docs; labelled keyboard-usable controls and textual chart equivalents | Platform and presentation contract not supplied | Readiness owner confirmation before scaffold/dashboard |
| A-08 | ISO uppercase country-code validation; reject null/invalid optional values rather than treating them as absent; malformed JSON policy and client-owned-field policy explicit | Missing fields have specified defaults; invalid fields need consistent behavior | Readiness confirms policy; ingestion documents complete contract before coding |
| A-09 | Explicit finite connection/insert/query deadlines; one attempt on writes; analytics invalid filters →422 and dependency failure →503 | Source specifies timeouts but no values or analytics failure codes | Readiness confirms policy; schema/client and analytics goals choose/document values |

## Open questions and return triggers

No missing information blocks this definition or creation of issues. All items below are deferred to readiness-safe bootstrap; they do block dependent product work until resolved.

- Owner: confirm proposed stack/component boundaries and A-02–A-09, including key strategy, timestamp precision, country/null/body policies, local-data lifecycle and UI/platform baseline. Review proposals together; do not silently accept defaults.
- Owner: confirm inherited MIT license/copyright and maintainership, human PR review/merge, product CI/release/rollback expectations. Existing LICENSE and adapter CI are evidence, not proof of a new product decision.
- Scaffold: pin compatible versions and record real commands and local binding; no runtime compatibility claims until tested.
- Schema/client: select library and transport, final sorting key, schema version procedure and timeout values using bounded investigation of the approved proposal.
- Generator: define whether count is total or per application (recommended total), deterministic identity/time handling and repeated-run behavior before coding. received_at can vary; reproducibility concerns logical generated events.
- Final benchmark: report query-cache configuration and warm-up procedure; first execution is not necessarily a cold OS/database cache. Explain that generator-direct insert does not benchmark HTTP ingestion throughput.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Retry after unknown write | Duplicate counts | No automatic retry; document caller responsibility |
| Incorrect isolation | Cross-application data exposed | Server-derived context and real integration tests |
| Miscounted distinct users | Misleading analytics | Exact aggregates and users returning on multiple days |
| Poor sorting for date-only queries | High scan work | Compare query shapes; measure rows/bytes, record trade-off |
| Large payload/generator | Resource exhaustion | Explicit byte/count bounds and streaming batches |
| Unauthenticated demo published | Data/configuration exposure | Local-only operation; public deployment excluded |
| Technical proposal mistaken for approval | Unreviewed architecture/security choices | Readiness confirmation and explicit decision statuses |

## First useful version and later versions

The smallest useful vertical slice is one application, HTTP ingestion and correct analytics with tests, after readiness/scaffold/schema. The complete MVP additionally includes dashboard, multi-application generator, service-backed CI and reproducible measurements. Later enhancements are uncommitted ideas outside the current backlog; they need a new scoped decision.

## Project decision status

`deferred` below never authorizes dependent product work. Reason and return trigger are explicit; none blocks the currently authorized definition/backlog task. No `default-accepted` is recorded without human confirmation.

| Area | Status | Value / notes | Link / location / return trigger |
|---|---|---|---|
| Product purpose | decided | Application event collection and analytics | Source #1 Goal; vision.md; D-001 |
| Users | decided | Application operators, API integrators and maintainers | Source #1 Goal; Users |
| Outcomes | decided | Reproducible ingestion → analytics → benchmark | Source #1 User journey; Goals |
| Success criteria | decided | Clean checkout, correct dashboard, CI and reproducible measurements | Source #1 MVP completion; Goals |
| First useful version | decided | Small end-to-end MVP; no platform expansion | Source #1 MVP requirements; First useful version |
| Non-goals | decided | Explicit exclusions preserved | Source #1 Out of scope; scope.md |
| Interfaces | decided | HTTP ingestion/analytics, local dashboard and operator commands | Source #1 §§1,3–6; FR-001/003/006/008/009 |
| Inputs and outputs | decided | Synthetic events, filters, counters/series, key and measurements | Source #1 §§1–6,9; data/output tables; encoding details deferred in A-02/04/05/08 |
| Architecture shape | deferred | Source technical proposal needs confirmation; no architecture selected by this definition | Owner/readiness: A-01 and boundaries before scaffold; does not block definition |
| Boundaries | deferred | Proposed Rails/PostgreSQL/ClickHouse responsibilities | Owner/readiness before product; does not block definition |
| Storage and data ownership | deferred | Proposed PG application/key digests, CH events, local synthetic operator data | Owner/readiness A-01/03/04/06; does not block definition |
| Retention and migrations | deferred | Versioned setup requested; TTL/reset/rebuild policy unspecified | Owner/readiness A-06; schema goal implements approved lifecycle; does not block definition |
| Integrations and failure handling | deferred | Source no-retry/unknown-write limits fixed; client/timeouts/status details proposed | Owner/readiness A-09; client goal records deadlines; does not block definition |
| Authentication and authorization | deferred | Bearer/application isolation required; digest mechanism and local dashboard trust need confirmation | Owner/readiness A-03 before auth work; does not block definition |
| Secrets, privacy, and sensitive data | decided | Synthetic only, digest-only keys, no key logging/browser exposure | Source #1 §§1,3,5,7; Security; D-002 |
| Language, framework, and dependencies | deferred | Proposed Rails/RSpec/Compose stack; versions and client unselected | Owner/readiness A-01, then scaffold pins; does not block definition |
| Environments and deployment | decided | Local demo only; public hosting excluded | Source #1 §5 and Out of scope; deployment mechanics in readiness |
| Configuration | deferred | Environment configuration/example required, names and timeout values unselected | Readiness approves policy; scaffold/client document real values; does not block definition |
| Logging, monitoring, and errors | deferred | Useful secret-free failures and separate liveness/readiness required; endpoint/log details open | Readiness/scaffold/client A-09; no hosted monitoring in local MVP; does not block definition |
| Tests, lint, typecheck, performance | deferred | Feature tests, real CH and reproducible benchmark required; tools/commands pending scaffold | Readiness A-01; first scaffold goal records real commands; does not block definition |
| Scale, reliability, and cost | decided | 1–1000 batch, 90-day query range, 1M demo; no latency gate/exactly-once | Source #1 §§3,4,6,8,9; numeric budgets unspecified, measure locally |
| Supported platforms and compatibility | deferred | No OS/runtime version promises supplied | Owner/readiness A-07; scaffold pins/tested matrix; does not block definition |
| Accessibility and localization | deferred | Language and minimum presentation baseline unspecified | Owner/readiness A-07 before dashboard; does not block definition |
| Compliance, backup, and recovery | deferred | Synthetic-only local demo; explicit rebuild needed, no backup target supplied | Owner/readiness A-06; document accepted local loss/recovery; does not block definition |
| Branching, CI, release, and rollback | deferred | GitHub adapter CI exists; product services and release policy unconfirmed | Owner/readiness confirms human review/merge and rollback; scaffold enables CI; does not block definition |
| License, ownership, and documentation expectations | deferred | LICENSE currently MIT ©2026 Szymon Iwacz; product confirmation missing; README obligations explicit | Owner/readiness confirms legal posture/maintenance; FR-012; does not block definition |

## Project readiness

Definition only; readiness has not been run. Use `.ai/onboarding/bootstrap-checklist.md` in the readiness issue. For this greenfield repository, real commands may be explicitly deferred to the first scaffold goal; do not create throwaway packaging to satisfy the gate.

| Check | Result | Notes |
|---|---|---|
| Definition coverage complete | complete | All 26 areas classified; proposals separate from confirmed intent |
| No `blocking-question` remains | yes for definition | No blocking-question status; deferred technical decisions must be revisited before product work |
| All `deferred` items have reason and return trigger | yes | Decision table and Open questions |
| Template customization complete | not assessed | Readiness issue owns this |
| Stack profile selected or marked N/A | pending | Rails candidate only |
| Real project commands recorded | deferred | No scaffold; first product goal owns actual commands |
| Root README describes the product | no | Still adapter README; readiness issue |
| `AGENTS.md` describes repository role | pending | Preserve workflow entrypoint, add product role during readiness |
| Bootstrap markers removed | not assessed | Whole-repository bootstrap review pending |
| License and ownership decided | pending | Confirm inherited license and maintainership |
| CI, branch rules, and approvals decided | pending | Product CI and owner policy pending |
| Project ready for first product task | not declared | No product implementation authorized or started |
