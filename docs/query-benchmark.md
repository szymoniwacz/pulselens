# Reproducible query benchmark

## Dataset and procedure

Use the generator in README with exactly 1,000,000 events, seed 42, generator version 1, and UTC range `[2026-11-01T00:00:00Z, 2026-12-01T00:00:00Z)`. The ordered two-application mapping determines event UUIDs; create fresh applications for a new generation. Keep HTTP demonstration events in a separate application. A repeat generation against the same pair appends duplicates and invalidates the fixture. No deletion, reset, cache flush or schema change is required.

After `bin/setup`, export the local `.env` and set `APP_ONE_ID` and `APP_TWO_ID` to the ordered UUIDs of the existing generated pair. Run the following read-only benchmark without concurrent inserts or other intentional workload:

```bash
set -a
source .env
set +a
RAILS_ENV=development APPLICATION_IDS="$APP_ONE_ID,$APP_TWO_ID" \
  bin/rails runner scripts/benchmark-queries.rb > /tmp/pulselens-benchmark.json
```

The runner checks that both applications exist and verifies total and distinct event counts (666,666 / 333,334), 256 exact users each, dimension cardinalities (4 names, 3 platforms, 5 countries), generator markers and timestamp bounds across all rows for each selected application. It rejects contaminated or incomplete fixtures. Seed is declared for existing data, not inferred from cardinalities. The runner records the actual ordered IDs, observed bounds, counts, software versions, host OS/CPU count/model/memory where available and Docker engine CPUs/memory and version. Missing metadata is null, not invented; the supplied Compose services have no explicit CPU/memory limits. The report describes the Docker engine resource pool, not per-query memory.

For an independent run with fresh IDs in the **test** databases:

```bash
RAILS_ENV=test BENCHMARK_GENERATE=1 bin/rails runner scripts/benchmark-queries.rb \
  > /tmp/pulselens-benchmark-repeat.json
```

The second command explicitly creates two test applications and a million new events using `scripts/verify-generator.rb`. It does not delete old data; allow sufficient disk space. Generator progress goes to stderr, the benchmark report to stdout. The separate Query benchmark workflow runs this mode on relevant changes or manual dispatch from GitHub Actions; the ordinary product CI uses small fixtures and has no timing gates. Raw JSON is retained as a workflow artifact.

## Exact measured workload

The runner calls the actual `EventAnalytics` service, using a benchmark-only subclass of the existing HTTP client that preserves the server's JSON statistics. No parallel SQL implementation or additional product dependency. It measures the first application's full 30-day range (the second app remains part of the dataset). Both shapes use the same bound `application`, `from` and `to` values. The dimension-filtered shape additionally binds `name=app_open`, `platform=ios`, `country=PL`.

Each shape runs five sequential repetitions in totals → daily → top names order. The report retains the exact SQL and typed parameter values for all six statements and raw samples per repetition. It also stores the full analytics result and SHA-256 digest, and checks equality across repeats. The SQL is sourced from the service, including `uniqExact`, date-first half-open predicates, UTC buckets and deterministic top-10 order. The date-only shape uses the application/date predicates; the dimension shape adds all three fixed equality predicates with AND.

Explicit request settings: `default_format=JSON`, `use_query_cache=0`, `use_query_condition_cache=0`, `output_format_write_statistics=1`; the shared transport supplies `wait_end_of_query=1` and its existing deadlines. See [ClickHouse JSON format](https://clickhouse.com/docs/interfaces/formats/JSON). The server's `statistics.elapsed` is in seconds; `rows_read` and `bytes_read` describe processed rows and uncompressed data, not physical disk I/O. `client_seconds` measures the monotonic interval around the bounded HTTP request and complete response body, including connection/transfer, excluding JSON parsing and Rails rendering. No HTTP ingestion throughput is measured here. The preflight reads the dataset before samples; caches and MergeTree background state may already be warm. No restart or OS/cache flush is attempted. Call the first sample **first observed**, not cold; report the remaining samples separately. Do not infer latency targets, PostgreSQL superiority or general performance from these observations.

## Observed generator run (local)

Owner terminal, 2026-11-25, Intel MacBook Pro, macOS 12.7.6, Ruby 3.4.13, Rails 8.1.4.1, Docker Engine 28.1.1, Compose 2.35.1, Docker VM 8 CPUs and 7.656 GiB memory (as reported by `docker info`). Pinned services from README. Development pair was created locally and generated with the parameters above. The dashboard showed 666,666 and 333,334 events, with 256 unique users each. The local generation command `/usr/bin/time -l env RAILS_ENV=development EVENT_COUNT=1000000 SEED=42 FROM=2026-11-01T00:00:00Z TO=2026-12-01T00:00:00Z APPLICATION_IDS=... bin/rails events:generate` reported:

| Metric | Observed |
|---|---:|
| Confirmed inserts | 1,000,000 |
| Maximum batch | 10,000 |
| Generation and synchronous insertion | 28.957 s |
| Generator process wall time | 31.10 s |
| Maximum resident set size | 117,833,728 bytes (112.38 MiB) |

The local generation process includes different work from the earlier CI verification runner (which also checks stored IDs/dimensions). Neither result is an HTTP ingestion rate or a controlled hardware comparison. Full local distinct-ID and dimension checks are performed by the benchmark preflight.

## Query measurement evidence

Pending the first actual benchmark runs. No query timings or read statistics are asserted yet. Commit the reviewed, credential-free raw reports and summarize first observed and subsequent samples here before closing #11. Compare identical query shapes and parameter mapping only with the dataset/environment differences explicitly noted.
