# PulseLens

PulseLens is an event analytics application built with Ruby on Rails and ClickHouse. It collects application events through an authenticated HTTP API and provides filtered analytics through a web dashboard.

**Status:** Rails scaffold, local infrastructure and versioned ClickHouse event storage/client. Application creation and digest-only API authentication are implemented. HTTP ingestion, analytics, dashboard, generator and full benchmarks remain planned.

## Architecture and versions

| Component | Pinned version | Responsibility |
|---|---|---|
| Ruby / Rails | 3.4.13 / 8.1.4.1 | Synchronous API, validation and a future server-rendered dashboard |
| PostgreSQL | 17.12 (Debian Bookworm image) | Application metadata and API key digests |
| ClickHouse | 26.8.46.6 | Event storage and future analytical aggregations |
| Docker Compose | v2 with `up --wait` | Local dependencies and persistent database volumes |
| RSpec Rails | 8.1.0 | Request, service and real-database integration tests |

Readiness still runs `SELECT 1` against each store. The internal event client and schema now support synchronous inserts and typed queries; PostgreSQL stores application metadata and key digests. HTTP ingestion and shared analytics queries belong to later goals. There are no queues, workers or cross-database transactions.

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

Future API endpoints inherit `Api::BaseController`, which accepts the key only in the `Authorization: Bearer <key>` request header. Missing, malformed and unknown credentials receive the same 401 response; a PostgreSQL lookup failure returns a generic 503. Application identity comes from the authenticated database record, never a client-supplied application ID. The health endpoints remain unauthenticated. No public ingestion or analytics route is added by this goal; request specs exercise the authentication boundary through a test-only route. This remains a loopback-only demo, not a production authentication service.

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

The internal `ClickhouseClient#insert_events` takes normalized symbol-keyed event hashes (including UTC-convertible Time values and a properties object). It sends one synchronous JSONEachRow insert. `#query(sql, bindings: {})` accepts trusted developer-authored SQL with typed placeholders such as `{application:UUID}` and passes escaped values as HTTP parameters, never SQL interpolation. Neither method is a public API yet. The client uses no ambient proxy or automatic retry, buffers the server response, rejects invalid or incomplete results and returns generic errors without raw server messages or causes. Whole-request deadlines are 15 seconds for queries/DDL and 30 seconds for inserts, connection deadline 2 seconds. Server execution limits are best-effort; a timed-out write may have committed. Repeating it can append duplicates.

Run `RUN_SERVICE_SPECS=1 bin/check` after setup. Storage integration tests use unique synthetic application IDs in the test database, and sorting experiments remove only their own unique test tables. Do not point test configuration at shared/production data.

## Planned MVP and limitations

The remaining flow is: create a demo application/key → submit synthetic batches → inspect exact application-scoped analytics → generate a reproducible million-event dataset and record query measurements. See [requirements](.ai/docs/project-requirements.md) and the [roadmap](.ai/project/roadmap.md).

- Local demo only: no public hosting, user accounts, roles or dashboard login.
- No real personal data, provider integrations, Kafka, queues or separate frontend.
- No deduplication or exactly-once guarantee. Inserts do not retry automatically: lost responses can leave writes unknown and repeated submissions can increase counters.
- No funnels, cohorts, retention/revenue analytics or materialized views.
- No performance results yet. Later benchmarks will document exact queries, dataset/environment and first/subsequent executions, without unsupported PostgreSQL comparisons.

## Project context and contribution

[Vision](.ai/project/vision.md) · [Product context](.ai/project/product-context.md) · [Scope](.ai/project/scope.md) · [Decisions](.ai/project/decisions.md) · [Glossary](.ai/project/glossary.md)

Review and merge remain with the owner. There are no automatic MVP releases; code rollback uses `git revert` and does not delete database volumes.

For authorized assisted development, follow [AGENTS.md](AGENTS.md). [Workflow setup](docs/setup.md), [adapter architecture](docs/architecture.md) and [automation setup](docs/automation-setup.md) describe the private workflow integration. After setup, `.ai/README.md` is its local entry point. This access is not required for the application or public checks above.

## License and maintainer

[MIT](LICENSE). Copyright ©2026 Szymon Iwacz. Maintainer: [szymoniwacz](https://github.com/szymoniwacz).
