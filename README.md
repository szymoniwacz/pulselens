# PulseLens

PulseLens is a small Ruby on Rails event analytics demo for learning ClickHouse and discussing backend design during recruitment. It is for a developer running a local synthetic-data demo and a reviewer exploring the architecture, tests and measurements.

**Status:** Rails scaffold, local infrastructure and versioned ClickHouse event storage/client. Application creation and digest-only API authentication are implemented. Authenticated synchronous HTTP ingestion, exact analytics and the synthetic event generator are available. The local dashboard is available. Full benchmarks remain planned.

## Architecture and versions

| Component | Pinned version | Responsibility |
|---|---|---|
| Ruby / Rails | 3.4.13 / 8.1.4.1 | Synchronous API, validation and a server-rendered dashboard |
| PostgreSQL | 17.12 (Debian Bookworm image) | Application metadata and API key digests |
| ClickHouse | 26.8.46.6 | Event storage and exact analytical aggregations |
| Docker Compose | v2 with `up --wait` | Local dependencies and persistent database volumes |
| RSpec Rails | 8.1.0 | Request, service and real-database integration tests |

Readiness still runs `SELECT 1` against each store. The internal event client and schema now support synchronous inserts and typed queries; PostgreSQL stores application metadata and key digests. The shared analytics service computes exact aggregates in ClickHouse. HTTP ingestion validates the complete batch before one synchronous insert. There are no queues, workers or cross-database transactions.

Versions and dependency rationale are recorded in [project decisions](.ai/project/decisions.md). Gem dependencies are locked in `Gemfile.lock`; runtime and service versions are fixed in `.ruby-version` and `compose.yaml`. The ClickHouse storage boundary uses Ruby's existing Net::HTTP and JSON libraries, without adding a gem.

## Clean local setup

Requirements: Linux or macOS, Ruby **3.4.13** with Bundler, and a running Docker engine with Compose v2. Ruby may be installed with your preferred version manager using `.ruby-version`. No Node.js or private AI workflow access is needed to run the product. Image CPU compatibility follows the [ClickHouse Docker requirements](https://clickhouse.com/docs/install/docker).

```bash
git clone https://github.com/szymoniwacz/pulselens.git
cd pulselens
cp .env.example .env
```

Edit `.env` and set **both** `POSTGRES_PASSWORD` and `CLICKHOUSE_PASSWORD` to local-only values. This file is ignored by Git and sourced by the shell wrappers, so quote values containing spaces or shell metacharacters. Keep the default usernames and ports unless you intentionally configure an alternative local setup.

```bash
bin/setup
bin/dev
```

`bin/setup` installs the locked gems into `vendor/bundle`, starts the Compose databases, prepares the development/test PostgreSQL databases and applies the versioned ClickHouse schemas. It does not reset an existing database or delete volumes. If `.env` is absent it creates the example and stops for configuration. `bin/dev` starts Rails on **127.0.0.1:3000**. Database ports are also published on loopback only (PostgreSQL 5432, ClickHouse HTTP 8123); no ClickHouse native port is published. If a port is occupied, stop the conflicting local service or adjust the documented configuration before starting.

## Create a demo application

After `bin/setup`, export your local configuration and run the operator command:

```bash
set -a
source .env
set +a
APPLICATION_NAME="Demo app" RAILS_ENV=development bin/rails applications:create
```

The command prints the application UUID and a cryptographically random 256-bit key (64 lowercase hexadecimal characters) once, only after a successful database insert. Save the key privately; PostgreSQL stores only its SHA-256 digest with a unique index. There is no command to recover, rotate or list plaintext keys. Do not paste the key into logs, screenshots, URLs or Git.

API endpoints inherit `Api::BaseController`, which accepts the key only in the `Authorization: Bearer <key>` request header. Missing, malformed and unknown credentials receive the same 401 response; a PostgreSQL lookup failure returns a generic 503. Application identity comes from the authenticated database record, never a client-supplied application ID. The health endpoints remain unauthenticated. The ingestion and analytics routes are available. This remains a loopback-only demo, not a production authentication service.

## Ingest events

After creating a demo application and starting `bin/dev`, set `API_KEY` privately to its saved key. Submit a JSON object with an `events` array (synthetic data only):

```bash
curl --fail-with-body http://127.0.0.1:3000/api/v1/events \
  --header "Authorization: Bearer $API_KEY" \
  --header 'Content-Type: application/json' \
  --data-binary @- <<'JSON'
{"events":[{"event_id":"00000000-0000-4000-8000-000000000001","name":"app_open","user_id":"synthetic-user-1","occurred_at":"2026-11-02T00:30:00+01:00","platform":"ios","country":"PL","properties":{"screen":"home"}}]}
JSON
```

A confirmed write returns HTTP 201 and `{"accepted":1}`. Use the same API key with the analytics example below to query the event (its UTC time is 2026-11-01 23:30). The example uses a fixed UUID; repeated submissions append duplicate events.

| Input | Validation |
|---|---|
| Request body | Maximum 2 MiB (2,097,152 bytes), including JSON whitespace |
| `events` | Array of 1–1000 objects; count and body limits both apply |
| `event_id` | UUID string, normalized to lowercase |
| `name` / `user_id` | Required nonblank strings, at most 128 / 256 UTF-8 bytes respectively |
| `occurred_at` | Timezone-bearing ISO-8601 timestamp, UTC years 1900–2299, seconds and optional 1–9 fractional digits; normalized to UTC and truncated to milliseconds |
| `platform` / `country` | `web`, `ios`, `android`, `unknown` / uppercase ISO 3166-1 alpha-2 or `unknown`; missing values default to `unknown` |
| `properties` | JSON object, at most 16 KiB (16,384 bytes) after compact JSON serialization; missing defaults to `{}` |
| `application_id` / `received_at` | Server assigned; reject either supplied at envelope or event level, including null |

Explicit nulls and incorrect types are invalid, including for optional fields. Unrecognized fields are ignored and never forwarded. The first invalid event produces HTTP 422, e.g. `{"error":"Invalid event batch","field":"name","index":1}`; indexes are zero-based, with `null` for envelope errors. Malformed JSON returns 400, missing/invalid Bearer credentials 401, oversized body 413, and unavailable storage 503. The transport size limit takes precedence over authentication; for within-limit requests authentication precedes JSON parsing. A server-level Puma 413 need not have a JSON body.

Puma's `http_content_length_limit` bounds request buffering (including chunked transfers). Early Rack middleware also reads at most 2 MiB + 1 byte before Rails parsing, for direct Rack callers and unknown or inaccurate length. It captures the raw body for the current sole POST endpoint and keeps it out of Rails' implicit parameter parser/logs, including malformed JSON. Adding another POST endpoint requires revisiting this middleware. The app does not log the Bearer key or raw request body; do not put keys in URLs or enable client-side verbose tracing. Real transport and application-level tests cover these boundaries.

Rails validates every event before calling the existing synchronous ClickHouse client exactly once. HTTP 201 is returned only after confirmed insertion. Validation prevents invalid-batch writes, not transactional guarantees during storage failures. A timeout or lost response can leave the last write outcome unknown; the API returns 503 without retrying. Repeating requests can increase counts even with the same event UUID.

## Query analytics

After creating an application, start `bin/dev` and supply the saved API key privately (do not include it in a URL or commit it). For example, in a shell with `API_KEY` already set:

```bash
curl --get --fail http://127.0.0.1:3000/api/v1/analytics \
  --header "Authorization: Bearer $API_KEY" \
  --data-urlencode 'from=2026-11-01T00:00:00Z' \
  --data-urlencode 'to=2026-11-04T00:00:00Z' \
  --data-urlencode 'platform=ios'
```

The response contains integer `total_events`, `unique_users`, `daily` (objects with `date`, `events`, `active_users`) and `top_events` (objects with `name`, `count`). For an application without events, the counters and daily buckets are zero and the top list is empty. Use the generator below to populate a demo dataset.

`from` and `to` are required ISO-8601 timestamps with `Z` or an explicit numeric offset; UTC years 1900–2299, seconds and optional fractional seconds (up to nine digits). The range must be positive and no longer than 90 elapsed days. Both bounds are normalized to UTC and rounded up to the next stored millisecond when needed, preserving inclusive-from/exclusive-to semantics. Daily buckets use UTC dates intersecting the original range, including partial days but excluding an exact-midnight end date. Optional filters: nonblank `name` up to 128 UTF-8 bytes, `platform` (web/ios/android/unknown), and uppercase ISO 3166-1 alpha-2 `country` or `unknown`. Filters combine with AND. Empty or invalid filter values return 422; missing/invalid credentials return 401; unavailable storage returns 503. Unknown query parameters cannot override the authenticated application identity.

`EventAnalytics` is shared with the dashboard and accepts a trusted server-selected application UUID and validated `AnalyticsFilters`. It runs three parameterized ClickHouse queries for exact range counts (`uniqExact`), daily counts and top ten ordered by count DESC/name ASC. Rails only converts counts to integers and fills missing dates. Each query has the existing 15-second client deadline (up to 45 seconds across three sequential queries, plus authentication and Rails overhead). No common snapshot across the three queries is promised while writes are concurrent. This local demo does not impose a latency threshold or offer production rate limiting.

## Local dashboard

After `bin/setup` and `bin/dev`, open <http://127.0.0.1:3000/>. Create at least one demo application using the operator command above and populate it through HTTP ingestion or the generator. Select the application by name and UUID, choose the UTC date range, optionally filter by exact event name, platform and country, then select **Apply filters**. To inspect the documented ingestion example, use 2026-11-01 as From and 2026-11-04 as To; for the generator example use 2026-11-01 and 2026-12-01.

The dashboard starts without a selected application; the default range covers the current UTC day and the preceding six days. Date inputs represent midnight UTC, with an inclusive start and exclusive end, at most 90 days. Blank optional controls mean no filter; invalid selections or filters display a 422 error. The API also supports sub-day timestamps; for equivalent midnight bounds both surfaces call the same `AnalyticsFilters` and `EventAnalytics` services. Application IDs are resolved against the server-side PostgreSQL list. The dashboard requests only application UUIDs and names, not key digests, and does not call its own HTTP API or put API keys in HTML, JavaScript, URLs or browser requests. The page has no JavaScript or external frontend dependency.

The counters show exact range totals and unique users; the grouped SVG chart shows daily events and active users on one scale, and the adjacent expandable table contains the exact values, including zero days. Top names retain the shared ordering and limit. No applications, no selection, no matching events, invalid filters and unavailable dependencies have explicit states; storage failures return 503 without presenting stale or partial results.

**Local trust boundary:** the dashboard is deliberately unauthenticated. It is restricted to development/test and local requests; run the supplied loopback-bound Puma configuration, and never expose it through a public bind, tunnel or reverse proxy. Local callers may select any demo application. Public access would require separate authentication and authorization and is outside the MVP.

Manual verification after setup: open the page with no selection; navigate labels, date inputs, selects, Apply and Reset with Tab and keyboard; inspect the chart and exact table on a narrow and a wide viewport; switch applications, apply filters, choose an empty range and check invalid-date and dependency-error states. With browser developer tools, verify that the GET request includes only UUID/date/filter fields and that no key or digest is present in the response or subsequent requests. Real-service request specs compare dashboard counters, daily values and top events to the authenticated API for identical filters. Browser/manual checks are additional to those specs.

## Liveness and readiness

```bash
curl --fail http://127.0.0.1:3000/up
curl --fail http://127.0.0.1:3000/ready
```

`/up` returns 200 when Rails is running without contacting either database. `/ready` returns JSON and 200 only after successful PostgreSQL and authenticated ClickHouse queries; otherwise it returns 503 with per-dependency `ok`/`unavailable` states. Responses and probe logs omit credentials, connection URLs and exception messages. Readiness responses are not cached.

Finite bootstrap limits: PostgreSQL application-pool wait/connect timeout is 2 seconds and server statement timeout is 1 second. Readiness uses a separate short-lived PostgreSQL connection with a 2-second client budget for name resolution, handshake and `SELECT 1`. It owns the connection before interruptible communication starts and always closes it, including on a stalled handshake or query; it never borrows or damages application-pool connections. ClickHouse has 2-second HTTP open/read/write limits and a 2-second deadline for the complete request, including continuously arriving partial responses, with automatic retries disabled and socket cleanup on interruption. The stores are checked sequentially, so these are not a 2-second deadline for the combined endpoint. The event client uses separate 2s connection, 15s whole-query and 30s whole-insert deadlines.

## Checks and build

The default specs exercise endpoint behavior, deadlines, failures and redaction without requiring live dependencies:

```bash
bin/check
```

After `bin/setup`, include the real PostgreSQL/ClickHouse integration specs:

```bash
RUN_SERVICE_SPECS=1 bin/check
```

The [cross-system coverage matrix](docs/integration-coverage.md) identifies which feature tests and full-journey checks cover each contract. The journey invokes the operator command, submits HTTP requests through Rails and compares actual ClickHouse rows and both analytics surfaces to independently specified expected values. To run only this journey after setup and exporting `.env`:

```bash
RAILS_ENV=test RUN_SERVICE_SPECS=1 bundle exec rspec spec/integration/cross_system_spec.rb
```

The normal suite uses small fixtures with fresh application UUIDs in the test databases; it does not delete existing data or run the million-event benchmark. Do not point test configuration at shared databases. The outage commands below temporarily stop the local Compose services, including any running demo, without deleting volumes.

`bin/check` runs RuboCop (Rails Omakase rules), RSpec and `RAILS_ENV=test bin/rails zeitwerk:check`. Individual commands, after exporting `.env` into your shell, are:

```bash
bundle exec rubocop
bundle exec rspec
RAILS_ENV=test bin/rails zeitwerk:check
RAILS_ENV=production SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile
```

The last command builds static CSS assets; `SECRET_KEY_BASE_DUMMY` is for asset compilation only, not deployment. There is no JavaScript build or static typechecker in this Ruby scaffold; Zeitwerk validates Rails autoloading, not types.

GitHub Actions retains the workflow adapter checks and adds a product job using the same pinned Compose services. It prepares the test database, runs real-service specs/lint/autoload checks, builds assets, simulates stalled PostgreSQL handshakes and queries to check the client deadline, socket cleanup, an unchanged application pool and recovery, then stops each database in turn to prove `/up` stays healthy while `/ready` returns 503. No arbitrary query-latency threshold is enforced.

To reproduce the controlled outage checks in an exported `.env` shell, with Rails tests using the test environment:

```bash
docker compose stop clickhouse
EXPECT_UNAVAILABLE=clickhouse bundle exec rspec spec/integration/outage_spec.rb
docker compose up -d --wait clickhouse
docker compose stop postgres
EXPECT_UNAVAILABLE=postgresql bundle exec rspec spec/integration/outage_spec.rb
docker compose up -d --wait postgres
```

Existing adapter checks still run without private workflow access:

```bash
bash -n scripts/*.sh tests/test-adapter.sh
bash tests/test-adapter.sh
bash scripts/check-workflow-leak.sh
```

The adapter tests use a local fixture; the leak check detects selected tracked private-workflow paths and is not a general secrets scanner.

## Configuration and data lifecycle

`.env.example` lists the supported settings. Wrappers `bin/setup`, `bin/dev` and `bin/check` load `.env`; direct Rails/Bundler commands use exported environment variables. PostgreSQL uses `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_USER`, `POSTGRES_PASSWORD`; database names are `pulselens_development` and `pulselens_test`. ClickHouse uses `CLICKHOUSE_URL`, `CLICKHOUSE_USER`, `CLICKHOUSE_PASSWORD`; URL credentials/query strings are rejected. Use a root HTTP(S) endpoint. `PORT` selects the loopback Rails port and `RAILS_MAX_THREADS` sets the Puma thread count/database pool size.

Use only local synthetic data. Ordinary restarts and `docker compose down` preserve named database volumes. Restart stopped dependencies with `docker compose up -d --wait`. Changing passwords in `.env` does not rewrite existing PostgreSQL volume credentials; retain the configured credentials or follow an intentional recovery procedure.

**Destructive reset, only when you explicitly intend to delete all local demo data:**

```bash
docker compose down --volumes
bin/setup
```

Do not run this against shared data. The setup command applies versioned ClickHouse SQL again; synthetic regeneration belongs to issue #9. No automatic TTL, reset, backup service or production deployment is included.

## ClickHouse event storage

Development and test use separate databases, `pulselens_development` and `pulselens_test`. Setup applies `db/clickhouse/001_create_events.sql`, an idempotent versioned statement, without dropping or truncating data. Later schema versions must also be safe to reapply. Run `RAILS_ENV=development bin/rails clickhouse:setup` (or test) in a shell with the documented environment exported to apply explicitly. A single local operator runs setup; it is not a concurrent migration service. Existing volumes keep their data; an explicitly authorized full local rebuild uses the destructive reset above.

The events table uses MergeTree, monthly UTC partitions, UUID application/event IDs, DateTime64(3, 'UTC') timestamps, String names/users/properties and LowCardinality(String) platform/country. JSON properties are serialized once as JSON text in a String column. The selected sorting key is `(application_id, occurred_at, name, event_id)`: application and bounded date filters are mandatory, whereas name is optional. The [sorting-key integration spec](spec/integration/clickhouse_sort_key_spec.rb) compares both candidates with 131,072 synthetic rows per table, two applications, eight event names and 28 days. In the [CI run for commit 276d80e](https://github.com/szymoniwacz/pulselens/actions/runs/45596923233), ClickHouse 26.8.46.6 reported these primary-key granule selections:

| Query shape | Date-first | Name-first |
| --- | --- | --- |
| Application + one day | 1/16 | 8/16 |
| Application + one day + event name | 1/16 | 1/16 |

Both keys returned the same counts for each shape. The date-first key is preferable for this workload; other distributions and wider ranges may behave differently. Granule selection is not a latency measurement. The full benchmark remains in #11.

The internal `ClickhouseClient#insert_events` takes normalized symbol-keyed event hashes (including UTC-convertible Time values and a properties object). It sends one synchronous JSONEachRow insert. `#query(sql, bindings: {})` accepts trusted developer-authored SQL with typed placeholders such as `{application:UUID}` and passes escaped values as HTTP parameters, never SQL interpolation. Both methods remain internal implementation boundaries behind the authenticated HTTP API. The client uses no ambient proxy or automatic retry, buffers the server response, rejects invalid or incomplete results and returns generic errors without raw server messages or causes. Whole-request deadlines are 15 seconds for queries/DDL and 30 seconds for inserts, connection deadline 2 seconds. Server execution limits are best-effort; a timed-out write may have committed. Repeating it can append duplicates.

Run `RUN_SERVICE_SPECS=1 bin/check` after setup. Storage integration tests use unique synthetic application IDs in the test database, and sorting experiments remove only their own unique test tables. Do not point test configuration at shared/production data.

## Generate synthetic data

After setup, create two distinct demo applications with `applications:create` as documented above. Save both UUIDs and their API keys privately. Set `APP_ONE_ID` and `APP_TWO_ID` to those UUIDs (not the API keys). In a shell with the local `.env` exported:

```bash
RAILS_ENV=development EVENT_COUNT=1000000 SEED=42 \
  FROM=2026-11-01T00:00:00Z TO=2026-12-01T00:00:00Z \
  APPLICATION_IDS="$APP_ONE_ID,$APP_TWO_ID" bin/rails events:generate
```

`EVENT_COUNT` is the **total** across exactly two existing applications, minimum two; the first receives about two-thirds and the second one-third. The ordered UUID pair is part of the dataset identity. The seed is an unsigned 64-bit integer. The range is half-open, timezone-bearing ISO-8601, within UTC years 1900–2299 and must contain at least one stored millisecond; unlike analytics, generation is not limited to 90 days. Use the saved key for either application with the analytics curl example above (adjust dates to query the generated range).

Generator version 1 uses Ruby's seeded `Random` on the pinned Ruby version, weighted time/user/name/platform/country selection and deterministic UUIDs from SHA-256 of the run identity and ordinal. Identical normalized count, seed, millisecond range, ordered application mapping and generator version reproduce the same logical rows, regardless of batch size. `received_at` records the time of the run and is excluded from logical equality. Only synthetic identifiers and properties are used.

The generator streams at most 10,000 rows per batch through the existing synchronous ClickHouse client; the entire dataset is never retained. It prints confirmed event count, batch limit and elapsed time. Repeated runs append duplicate logical events, so use fresh demo applications for isolated measurements. No implicit deletion, reset or retry occurs. A failed batch stops generation; the printed confirmed count is a lower bound because the last write may have committed. Never blindly retry an ambiguous write.

### Verify a million events

The verification runner creates two new isolated test applications, invokes the real generator command and checks exact stored counts, distinct event IDs, returning users, dimensions and date range using ClickHouse. It does not print API keys or delete data. With local test services prepared and the environment exported:

```bash
RAILS_ENV=test bin/rails runner scripts/verify-generator.rb
```

On Linux, prefix with `/usr/bin/time -v` to record wall time and peak generator-process RSS (not ClickHouse server memory); on macOS use `/usr/bin/time -l`. The separate Generator verification GitHub Actions workflow runs this against real services for relevant pull requests and supports manual dispatch after merge. No latency target is asserted. This verifies the direct insert path, **not HTTP ingestion throughput**. Use the separate [HTTP ingestion example](#ingest-events) to exercise the authenticated HTTP path; the direct insertion measurements below do not cover it.

### Observed million-event verification

[GitHub Actions run 45628527347](https://github.com/szymoniwacz/pulselens/actions/runs/45628527347), 2026-11-25, commit `f2f8098`, generator v1. GitHub-hosted Ubuntu 26.04 x86_64 (image 20261116.88.1), Ruby 3.4.13, Rails 8.1.4.1, PostgreSQL 17.12 and ClickHouse 26.8.46.6; test database, seed 42, UTC range `[2026-11-01T00:00:00Z, 2026-12-01T00:00:00Z)`. The ordered application mapping for this run is recorded in the job log (first `c74b5045-3a09-41f0-8f23-68f1e4429ad5`, second `41907a71-eec0-4b4d-a8d0-d50eb1b180d6`).

| Metric | Observed value |
|---|---:|
| Confirmed events / distinct event UUIDs | 1,000,000 / 1,000,000 |
| Events per application (first / second) | 666,666 / 333,334 |
| Unique synthetic users per application | 256 |
| Event names / platforms / countries per application | 4 / 3 / 5 |
| Batches / maximum rows per batch | 100 / 10,000 |
| Generation and synchronous insertion elapsed | 11.019 s |
| Rails runner wall time, including verification | 12.38 s |
| Peak runner-process RSS | 144,120 KiB (140.74 MiB) |

The SQL verification confirmed all expected counts and UTC bounds. This is a single CI observation, not a local workstation run, a memory-scaling experiment, a server-memory measurement or an HTTP/analytics benchmark. A fresh application mapping changes event UUIDs; repeat an identical mapping and seed to reproduce logical events, but remember that inserts append duplicates. Query benchmarking remains in #11.

## Planned MVP and limitations

The remaining full MVP work includes cross-system coverage and reproducible query measurements. See [requirements](.ai/docs/project-requirements.md) and the [roadmap](.ai/project/roadmap.md).

- Local demo only: no public hosting, user accounts, roles or dashboard login.
- No real personal data, provider integrations, Kafka, queues or separate frontend.
- No deduplication or exactly-once guarantee. Inserts do not retry automatically: lost responses can leave writes unknown and repeated submissions can increase counters.
- No funnels, cohorts, retention/revenue analytics or materialized views.
- No analytics query benchmark results yet. Later benchmarks will document exact queries, dataset/environment and first/subsequent executions, without unsupported PostgreSQL comparisons.

## Project context and contribution

[Vision](.ai/project/vision.md) · [Product context](.ai/project/product-context.md) · [Scope](.ai/project/scope.md) · [Decisions](.ai/project/decisions.md) · [Glossary](.ai/project/glossary.md)

Review and merge remain with the owner. There are no automatic MVP releases; code rollback uses `git revert` and does not delete database volumes.

For authorized assisted development, follow [AGENTS.md](AGENTS.md). [Workflow setup](docs/setup.md), [adapter architecture](docs/architecture.md) and [automation setup](docs/automation-setup.md) describe the private workflow integration. After setup, `.ai/README.md` is its local entry point. This access is not required for the application or public checks above.

## License and maintainer

[MIT](LICENSE). Copyright ©2026 Szymon Iwacz. Maintainer: [szymoniwacz](https://github.com/szymoniwacz).
