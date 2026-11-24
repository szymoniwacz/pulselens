# Project Requirements

Revision: definition-3, 2026-11-24. Source: [issue #1](https://github.com/szymoniwacz/pulselens/issues/1), no comments at initial definition time. Owner confirmations: conversation dated 2026-11-24, recorded as D-004–D-010 in [decisions](../project/decisions.md). Backlog: [roadmap](../project/roadmap.md).

## Project summary

PulseLens is a small local event analytics portfolio demo for practical ClickHouse learning and backend design discussion. A developer creates an application, submits synthetic events, views correct filtered analytics and reproduces measurements over one million events. A reviewer follows the README from a clean checkout.

The source establishes product intent and requested behavior; it explicitly labels technical design as a proposal. Below, functional requirements preserve the requested MVP contract. Proposed implementation details and additional defaults are not approved architecture. Confirm them during readiness before product implementation.

## Users

| User | Needs | Notes |
|---|---|---|
| Developer/maintainer | Operate the demo, understand storage/query trade-offs | Local synthetic data only |
| Recruiter/reviewer | Reproduce behavior, inspect tests and measurements | No public hosting or login required |

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

All rows are must-have MVP outcomes from issue #1 plus explicit owner clarifications D-004–D-010. Technical representations remain proposals where marked.

| ID | Requirement | Verification |
|---|---|---|
| FR-001 | Command creates application with UUID, name, key digest and timestamps; cryptographically random key shown once, digest only stored; Bearer auth; no key logging | Creation, persistence and authentication specs; log inspection |
| FR-002 | Events contain authenticated application_id, client event_id UUID, required name/user_id, occurred_at and server received_at, platform/country and object properties; versioned ClickHouse setup | Schema and real-database round trip |
| FR-003 | POST /api/v1/events accepts 1–1000 events; validates all before one batch insert; rejects client-supplied application_id or received_at with 422; no automatic insert retry | Request specs plus real ClickHouse; prove invalid batch writes nothing |
| FR-004 | Missing platform/country → unknown; missing properties → {}; timestamp timezone required, normalize UTC; explicit field/properties/body limits; errors identify zero-based index and field | Boundary and normalization specs |
| FR-005 | Ingestion: 201 only after confirmed insert with accepted count; 401 missing/invalid key; 400 malformed JSON; 413 oversized body; 422 invalid batch or client-supplied server-reserved fields; 503 ClickHouse unavailable | HTTP contract and dependency-failure specs |
| FR-006 | GET /api/v1/analytics uses Bearer key; required from/to, from < to, at most 90 days, UTC [from,to); optional name/platform/country combine with AND; safe binding and application scope in every query; invalid filters return 422, unavailable dependency returns 503 | Filter, injection, isolation and timestamp boundary tests |
| FR-007 | ClickHouse computes total events, exact range unique users, daily events and exact daily users, top 10 names; ties ordered count DESC/name ASC, daily UTC dates intersecting [from,to) (excluding an exact-midnight to day), zero days, zero empty counters and empty top list | Known fixture comparisons; repeated users across days; partial-day/empty ranges |
| FR-008 | Local single-page dashboard: server-side application selection, dates and dimension filters, counters, daily chart, top table, empty/error states; same analytics service; no keys sent to browser | System/request checks; API/dashboard parity; rendered output inspection |
| FR-009 | Generator accepts event count, date range and seed; at least two applications, returning users, multiple names/platforms/countries, reproducible nonuniform activity; bounded-memory batches; supports 1 million events; no implicit deletion | Fixed-seed equality, count/distribution checks, multi-batch test and full demo run |
| FR-010 | Environment config and secret-free example; explicit connection/query timeouts; versioned schema; documented rebuild; separate liveness and dependency readiness; useful secret-free errors | Fresh setup, unavailable dependency checks and rebuild documentation |
| FR-011 | Tests ship with features; RSpec and real ClickHouse integration proposed; GitHub Actions CI runs required services and meaningful checks without latency gates | Feature evidence plus cross-system coverage matrix and green CI |
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
| country | Client | Two-letter code or unknown; absent defaults unknown; uppercase ISO country-code validation accepted (A-08) |
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

Proposed architecture: synchronous Rails API/dashboard → PostgreSQL for applications/key digests; ClickHouse for events/aggregations. Docker Compose is confirmed for local operation (D-004) and GitHub Actions for CI (D-007); RSpec remains proposed. No queues or cross-store transactions. Keep analytics SQL/service shared between API and dashboard. PostgreSQL failure must fail authentication safely; do not mistake process liveness for database readiness.

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

## Proposal approval register

Approval source: owner's conversation reply dated 2026-11-24, recorded in D-004–D-010. Accepted policy is distinct from implemented behavior. No product readiness or execution authorization is implied.

| ID | Status | Value / remaining choice | Confirmation / return trigger |
|---|---|---|---|
| A-01 | partially approved | GitHub Actions and Docker Compose accepted. Rails monolith, PostgreSQL + ClickHouse responsibilities and RSpec still proposed | Owner confirms remaining stack/boundaries in #2; compatible versions delegated to #3 |
| A-02 | unapproved | name ≤128 UTF-8 bytes, user_id ≤256 bytes, properties serialized JSON ≤16 KiB/event, body ≤2 MiB | Owner confirms before ingestion; limits apply together, so 1000 individually valid large events need not fit |
| A-03 | unapproved | SHA-256 digest of at least 256 random key bits, indexed digest lookup | Owner security confirmation before #4 |
| A-04 | partially delegated | DateTime64(3, UTC) and monthly partitions still proposed; final sorting key is delegated, not selected | Owner confirms precision/partition policy in #2; #5 selects and justifies sorting key/library/transport |
| A-05 | approved | Top ties count DESC/name ASC; zero-based error indexes; daily UTC dates intersecting [from,to), excluding an exact-midnight to day | D-009; #6/#7 document and test the confirmed contract |
| A-06 | approved | Persistent local database volumes preserve data across ordinary restarts. Generator recovery, explicit-command-only deletion and no automatic TTL remain confirmed; production backup service outside MVP | D-007/D-010; #3/#5 document volume lifecycle; no blanket reset authorization |
| A-07 | approved | Local Linux/macOS with Compose; English UI/docs; labelled keyboard-usable controls and textual chart equivalents | D-004; actual runtime versions and tested compatibility recorded in #3 |
| A-08 | approved with clarification | Uppercase ISO country codes; reject null/invalid optional values; malformed JSON →400; client-supplied server-reserved application_id/received_at →422 | D-005; ingestion #6 documents and tests the contract |
| A-09 | approved; values delegated | Finite connection/insert/query deadlines, one write attempt; analytics invalid filters →422, dependency failure →503 | D-006; #5/#7 choose and justify actual timeout values |

## Open questions and return triggers

No missing information blocks this documentation update. Unapproved policy choices below remain prerequisites for dependent product work; they do not prevent definition coverage.

- Owner in #2: remaining A-01 stack/boundaries, A-02 input limits, A-03 key design, A-04 timestamp precision/partitions. A-05–A-09 no longer require reconfirmation.
- Confirmed ownership baseline: retain the existing LICENSE attribution ©2026 Szymon Iwacz; review and merge remain with the repository owner. MIT, GitHub Actions, no automatic MVP releases, git revert rollback and generator recovery with explicit deletion are confirmed; no additional maintenance commitment is invented.
- Delegated by owner, not a new approval question: #3 selects and justifies compatible versions; #5 selects and justifies ClickHouse library/transport, final sorting key and client timeouts; #7 records any analytics-specific timeout choice. Select within approved component/security/data boundaries and escalate only material scope changes.
- Scaffold: record real commands and local binding; no runtime compatibility claims until tested. Customization and profile selection remain in #2; no scaffold is created during this documentation task.
- Generator #9: define whether count is total or per application (recommended total), deterministic identity/time handling and repeated-run behavior before coding. received_at can vary; reproducibility concerns logical generated events.
- Final benchmark #11: report query-cache configuration and warm-up procedure; first execution is not necessarily a cold OS/database cache. Explain that generator-direct insert does not benchmark HTTP ingestion throughput.

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
| Product purpose | decided | Local ClickHouse learning and portfolio demo | Source #1 Goal; vision.md; D-001 |
| Users | decided | Developer and recruitment reviewer | Source #1 Goal; Users |
| Outcomes | decided | Reproducible ingestion → analytics → benchmark | Source #1 User journey; Goals |
| Success criteria | decided | Clean checkout, correct dashboard, CI and reproducible measurements | Source #1 MVP completion; Goals |
| First useful version | decided | Small end-to-end MVP; no platform expansion | Source #1 MVP requirements; First useful version |
| Non-goals | decided | Explicit exclusions preserved | Source #1 Out of scope; scope.md |
| Interfaces | decided | HTTP ingestion/analytics, local dashboard and operator commands | Source #1 §§1,3–6; FR-001/003/006/008/009 |
| Inputs and outputs | decided | Synthetic events, filters, counters/series and key; malformed JSON 400, server-reserved fields 422 | Source #1; D-005; data/output tables; A-02/04 encoding details pending; A-05 confirmed by D-009 |
| Architecture shape | deferred | Source technical proposal needs confirmation; no architecture selected by this definition | Owner/readiness: A-01 and boundaries before scaffold; does not block definition |
| Boundaries | deferred | Proposed Rails/PostgreSQL/ClickHouse responsibilities | Owner/readiness before product; does not block definition |
| Storage and data ownership | deferred | Proposed PG application/key digests, CH events, local synthetic operator data | Owner/readiness A-01/03/04; persistent volumes confirmed D-010; does not block definition |
| Retention and migrations | decided | Versioned setup required; persistent volumes across ordinary restarts; generator recovery, explicit-command-only deletion and no automatic TTL confirmed | Source #1 §7; D-007/D-010; #3/#5 implement and document lifecycle |
| Integrations and failure handling | decided | No write retry; finite deadlines; analytics invalid filters 422/unavailable dependency 503; actual client/timeouts delegated | D-006/D-008; #5/#7 record and justify library/deadline values |
| Authentication and authorization | deferred | Bearer/application isolation required; digest mechanism and local dashboard trust need confirmation | Owner/readiness A-03 before auth work; does not block definition |
| Secrets, privacy, and sensitive data | decided | Synthetic only, digest-only keys, no key logging/browser exposure | Source #1 §§1,3,5,7; Security; D-002 |
| Language, framework, and dependencies | deferred | Rails/RSpec remain proposed; Compose confirmed; versions and client delegated | Owner/readiness A-01, then scaffold pins; does not block definition |
| Environments and deployment | decided | Local demo only; public hosting excluded | Source #1 §5 and Out of scope; deployment mechanics in readiness |
| Configuration | deferred | Environment config/example required; timeout policy accepted and values delegated; variable names follow scaffold/client | D-006/D-008; #3/#5 document actual config; does not block definition |
| Logging, monitoring, and errors | deferred | Secret-free failures/liveness vs readiness required; 400/422 contracts accepted; endpoint/log details pending scaffold | D-005/D-006; #3/#5 record details; does not block definition |
| Tests, lint, typecheck, performance | deferred | Feature tests, real CH and reproducible benchmark required; tools/commands pending scaffold | Readiness A-01; first scaffold goal records real commands; does not block definition |
| Scale, reliability, and cost | decided | 1–1000 batch, 90-day query range, 1M demo; no latency gate/exactly-once | Source #1 §§3,4,6,8,9; numeric budgets unspecified, measure locally |
| Supported platforms and compatibility | decided | Local Linux/macOS with Compose; compatible runtime versions delegated and must be tested | D-004/D-008; #3 pins versions and records tested matrix |
| Accessibility and localization | decided | English UI/docs; labelled keyboard-usable controls, textual chart equivalents | D-004; #8 dashboard verification |
| Compliance, backup, and recovery | decided | Synthetic local demo; recreate demo data with generator; deletion requires explicit command; production backup service is outside the local MVP | D-002/D-007; #5/#9/#11 document recovery; no unrequested deletion |
| Branching, CI, release, and rollback | decided | GitHub Actions; review and merge by owner; no automatic MVP releases; code rollback via git revert | D-007; policies only, no repository-settings changes authorized |
| License, ownership, and documentation expectations | decided | MIT confirmed; existing ©2026 Szymon Iwacz retained; repository owner reviews/merges; README obligations explicit | LICENSE; D-007; FR-012 |

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
| License and ownership decided | confirmed | MIT; existing LICENSE attribution retained; owner reviews and merges (D-007) |
| CI, branch rules, and approvals decided | policy confirmed | D-007; implementation/customization and gate evidence still pending |
| Project ready for first product task | not declared | No product implementation authorized or started |
