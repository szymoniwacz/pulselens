# Integration coverage

Issue #10 closes cross-system gaps without replacing the feature-owned tests. All examples use synthetic data and the separate local test databases (`pulselens_test`). Applications have fresh UUIDs; fixtures do not depend on an empty database, do not truncate data, and do not modify development data. The full journey goes through the real Rails request stack, PostgreSQL and ClickHouse; the Puma transport test separately exercises actual TCP/HTTP framing. No new product dependencies, schema changes or performance thresholds are introduced.

| Contract | Feature evidence | Cross-system evidence |
|---|---|---|
| Operator creates application/key; digest-only authentication | `application_creation_task_spec.rb`, `application_authentication_spec.rb`, `application_api_key_spec.rb` | `cross_system_spec.rb`: real operator subprocess, HTTP insertion for two fresh applications and exact stored event IDs |
| Invalid or missing key; whole-batch validation and server fields | `events_spec.rb`, `event_batch_spec.rb`, `event_ingestion_spec.rb` | Journey rejects missing, malformed and unknown keys on both endpoints; rejects mixed invalid batches and checks both applications' stored rows remain unchanged |
| Body, field and batch limits; malformed JSON | `ingestion_body_spec.rb`, `events_spec.rb`, `event_batch_spec.rb`, `ingestion_transport_spec.rb` | Journey confirms no write after 1001 rows, malformed JSON and a body over 2 MiB; feature tests retain exact-boundary coverage and real Puma framing checks |
| Application isolation, UTC offsets, half-open ranges, exact unique users, zero days | `analytics_spec.rb`, `analytics_filters_spec.rb`, `event_analytics_spec.rb`, `event_ingestion_spec.rb` | Journey compares known rows from HTTP ingestion with independently specified totals, daily series and top names on API and dashboard, including offset normalization and excluded endpoints |
| Individual and combined dimensions; empty results; top-name ordering | `analytics_spec.rb`, `dashboard_spec.rb`, `event_analytics_spec.rb` | Journey checks combined AND filters and empty results against fixed expected values; feature specs retain individual filters and top-ten tie-order coverage |
| Dashboard uses local server context without keys | `spec/requests/dashboard_spec.rb`, `spec/integration/dashboard_spec.rb` | Journey checks rendered totals, daily/top tables and absence of both applications' keys and digests |
| Service failure, finite deadlines, no retry on ambiguous writes | `clickhouse_transport_spec.rb`, `clickhouse_client_spec.rb`, `dependency_readiness_spec.rb`, `postgresql_stall_spec.rb`, `events_spec.rb` | `outage_spec.rb` runs with each service actually stopped; both API endpoints and dashboard return 503, `/up` remains healthy and `/ready` identifies the stopped service |
| Deterministic bounded generation | `synthetic_event_generator_spec.rb`, `scripts/verify-generator.rb`, `generator-verification.yml` | Generator remains a separate verification workflow; normal product CI does not generate one million events on every run |

Except for the explicitly qualified paths, spec names refer to files under `spec/`. These are coverage mappings, not a claim that the new checks have passed before CI runs.

## Reproduce

From a clean checkout, use the README setup instructions with local-only passwords, then run `RUN_SERVICE_SPECS=1 bin/check`. This runs real service examples, lint and autoload checks. The targeted journey command is in the README. Use the README's controlled outage procedure only on local demo services; it stops the selected dependency temporarily and does not remove volumes. CI provisions services, prepares both schemas, runs the full product checks and asset build, then exercises actual outages and stops services without deleting volumes. Adapter checks are separate. CI service diagnostics use container status rather than raw database logs; the journey captures one-time command output in memory, never prints the key and uses boolean credential checks to avoid revealing actual credentials in new assertions. Do not paste logs or keys into public issues.

No arbitrary latency limit or benchmark is included here. Issue #11 owns final measurements and the clean-checkout walkthrough. Request specs are not full browser automation; manual dashboard validation is recorded in PR #20.
