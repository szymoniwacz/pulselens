# PulseLens

PulseLens is a small Ruby on Rails event analytics demo for learning ClickHouse and discussing backend design during recruitment. It is intended for a developer running a local demo and a reviewer exploring the architecture, tests and measurements.

**Status:** project definition and repository bootstrap. The MVP is specified and its product decisions are approved; the Rails application has not been implemented. This repository does not yet offer a running API, dashboard or generator.

## Planned MVP

1. Create a demo application and receive an API key, displayed once and stored only as a digest.
2. Submit synthetic event batches to `POST /api/v1/events`.
3. Explore application-scoped analytics through `GET /api/v1/analytics` and a simple dashboard.
4. Generate a reproducible dataset for at least two applications and measure queries over one million events.

The analytics include total events, exact unique users, daily activity and top event names, with date and dimension filters. Tests will accompany each feature and include real ClickHouse integration.

## Architecture

| Component | Responsibility |
|---|---|
| Ruby on Rails | Synchronous HTTP API, authentication, validation, shared analytics query logic and server-rendered dashboard |
| PostgreSQL | Demo application configuration and API key digests |
| ClickHouse | Event storage and analytical aggregations |
| Docker Compose | Local dependencies with persistent database volumes |
| RSpec / GitHub Actions | Feature/integration tests and CI |

PostgreSQL holds application metadata; ClickHouse holds event data and computes aggregates. There are no background workers or cross-database transactions. Versions, the ClickHouse library, timeout values and the final sorting key will be selected and justified in the corresponding implementation tasks.

## Start here

Clone the repository to inspect the definition and run the existing repository checks:

```bash
git clone https://github.com/szymoniwacz/pulselens.git
cd pulselens
```

Application installation, startup, build, test, lint and typecheck commands do not exist yet. [Scaffold issue #3](https://github.com/szymoniwacz/pulselens/issues/3) will provide the actual commands, compatible versions and local dependency setup. No Rails or Docker commands below are implied to work before that task is delivered.

Application/key creation, HTTP examples, schema setup/rebuild, generator commands and benchmark results will be documented with their implementing features. The [roadmap](.ai/project/roadmap.md) records the prerequisites and sequence.

## Configuration and local data

The MVP targets local Linux/macOS environments using Docker Compose and synthetic data only. Application environment variables, finite connection/query timeouts and a secret-free `.env.example` will be documented in the scaffold/client tasks; no product environment configuration is available yet.

Database volumes will preserve data across ordinary restarts. Deletion requires an explicit command; there is no automatic TTL. Demo data can be recreated with the planned generator. Never commit or log API keys; the dashboard will keep them out of the browser.

## Existing repository checks

These checks validate the inherited workflow adapter, not an implemented Rails product. They run without access to the private workflow repository:

```bash
bash -n scripts/*.sh tests/test-adapter.sh
bash tests/test-adapter.sh
bash scripts/check-workflow-leak.sh
```

The contract tests use a local fixture. The leak check detects selected tracked private-workflow paths; it is not a general secrets scanner. GitHub Actions runs these checks on pushes and pull requests. Product CI with real PostgreSQL/ClickHouse services belongs to issue #3 and subsequent feature tasks.

## Scope and limitations

- Local demo only: no public hosting, user accounts, roles or dashboard login.
- No real personal data or integrations with analytics providers.
- Synchronous ingestion only; no queues, Kafka or separate frontend.
- No deduplication or exactly-once guarantee. Inserts are not retried automatically; a lost response can leave the write outcome unknown, and repeated submissions can increase counters.
- No funnels, cohorts, retention or revenue analytics, or materialized views.
- No performance results exist yet. Benchmarks will record the dataset, environment, exact queries and first/subsequent executions without arbitrary CI latency thresholds or unsupported PostgreSQL comparisons.

## Project context and contribution

- [Vision](.ai/project/vision.md), [product context](.ai/project/product-context.md) and [scope](.ai/project/scope.md).
- [Requirements, approvals and readiness](.ai/docs/project-requirements.md), [decisions](.ai/project/decisions.md) and [glossary](.ai/project/glossary.md).
- [Roadmap and linked issues](.ai/project/roadmap.md); source [#1](https://github.com/szymoniwacz/pulselens/issues/1), readiness [#2](https://github.com/szymoniwacz/pulselens/issues/2), first product task [#3](https://github.com/szymoniwacz/pulselens/issues/3).

The repository uses a private reusable AI workflow for authorized contributors. [Workflow setup and troubleshooting](docs/setup.md), [architecture](docs/architecture.md) and [automation setup](docs/automation-setup.md) describe that adapter infrastructure. Follow [AGENTS.md](AGENTS.md); after setup, `.ai/README.md` and `.ai/docs/template-flow.md` are the local workflow entry points. Private workflow access is required for assisted development, not for the public repository checks above. The future product must run without that access.

Review and merge remain with the repository owner. There are no automatic MVP releases; code rollback uses `git revert`. Product implementation requires a separately authorized task after readiness and integration checks.

## License and maintainer

[MIT](LICENSE). Copyright ©2026 Szymon Iwacz. Maintainer: [szymoniwacz](https://github.com/szymoniwacz).
