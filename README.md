# PulseLens

PulseLens is a small Ruby on Rails event analytics demo for learning ClickHouse and discussing backend design during recruitment. It is for a developer running a local synthetic-data demo and a reviewer exploring the architecture, tests and measurements.

**Status:** runnable Rails scaffold and local infrastructure. `/up` and `/ready` are implemented. Application/key creation, event ingestion, analytics, dashboard, generator and benchmarks remain planned in [issues #4–#11](.ai/project/roadmap.md).

## Architecture and versions

| Component | Pinned version | Responsibility |
|---|---|---|
| Ruby / Rails | 3.4.13 / 8.1.4.1 | Synchronous API, validation and a future server-rendered dashboard |
| PostgreSQL | 17.12 (Debian Bookworm image) | Future application metadata and API key digests |
| ClickHouse | 26.8.46.6 | Future event storage and analytical aggregations |
| Docker Compose | v2 with `up --wait` | Local dependencies and persistent database volumes |
| RSpec Rails | 8.1.0 | Request, service and real-database integration tests |

The current readiness probe only runs `SELECT 1` against each store. There is no event client, schema or domain model yet. SQL aggregation and shared dashboard/API queries belong to later goals. There are no queues, workers or cross-database transactions.

Versions and dependency rationale are recorded in [project decisions](.ai/project/decisions.md). Gem dependencies are locked in `Gemfile.lock`; runtime and service versions are fixed in `.ruby-version` and `compose.yaml`. The ClickHouse analytics library, event schema and sorting key remain for issue #5.

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

`bin/setup` installs the locked gems into `vendor/bundle`, starts the Compose databases and prepares the empty development/test PostgreSQL databases. It does not reset an existing database or delete volumes. If `.env` is absent it creates the example and stops for configuration. `bin/dev` starts Rails on **127.0.0.1:3000**. Database ports are also published on loopback only (PostgreSQL 5432, ClickHouse HTTP 8123); no ClickHouse native port is published. If a port is occupied, stop the conflicting local service or adjust the documented configuration before starting.

## Liveness and readiness

```bash
curl --fail http://127.0.0.1:3000/up
curl --fail http://127.0.0.1:3000/ready
```

`/up` returns 200 when Rails is running without contacting either database. `/ready` returns JSON and 200 only after successful PostgreSQL and authenticated ClickHouse queries; otherwise it returns 503 with per-dependency `ok`/`unavailable` states. Responses and probe logs omit credentials, connection URLs and exception messages. Readiness responses are not cached.

Finite bootstrap limits: PostgreSQL connection/pool wait 2 seconds and statement timeout 1 second; ClickHouse HTTP open/read/write timeouts 2 seconds each, with automatic retries disabled. These are per-operation limits, not a guarantee that the combined endpoint finishes within 2 seconds. The event client's insert/query limits will be designed in issue #5.

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

GitHub Actions retains the workflow adapter checks and adds a product job using the same pinned Compose services. It prepares the test database, runs real-service specs/lint/autoload checks, builds assets, then stops each database in turn to prove `/up` stays healthy while `/ready` returns 503. No arbitrary query-latency threshold is enforced.

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

Do not run this against shared data. There are no event tables to rebuild yet; versioned ClickHouse schema setup belongs to issue #5 and synthetic regeneration to issue #9. No automatic TTL, reset, backup service or production deployment is included.

## Planned MVP and limitations

The remaining flow is: create a demo application/key → submit synthetic batches → inspect exact application-scoped analytics → generate a reproducible million-event dataset and record query measurements. See [requirements](.ai/docs/project-requirements.md) and the [roadmap](.ai/project/roadmap.md).

- Local demo only: no public hosting, user accounts, roles or dashboard login.
- No real personal data, provider integrations, Kafka, queues or separate frontend.
- No deduplication or exactly-once guarantee. Future inserts will not retry automatically: lost responses can leave writes unknown and repeated submissions can increase counters.
- No funnels, cohorts, retention/revenue analytics or materialized views.
- No performance results yet. Later benchmarks will document exact queries, dataset/environment and first/subsequent executions, without unsupported PostgreSQL comparisons.

## Project context and contribution

[Vision](.ai/project/vision.md) · [Product context](.ai/project/product-context.md) · [Scope](.ai/project/scope.md) · [Decisions](.ai/project/decisions.md) · [Glossary](.ai/project/glossary.md)

Review and merge remain with the owner. There are no automatic MVP releases; code rollback uses `git revert` and does not delete database volumes.

For authorized assisted development, follow [AGENTS.md](AGENTS.md). [Workflow setup](docs/setup.md), [adapter architecture](docs/architecture.md) and [automation setup](docs/automation-setup.md) describe the private workflow integration. After setup, `.ai/README.md` is its local entry point. This access is not required for the application or public checks above.

## License and maintainer

[MIT](LICENSE). Copyright ©2026 Szymon Iwacz. Maintainer: [szymoniwacz](https://github.com/szymoniwacz).
