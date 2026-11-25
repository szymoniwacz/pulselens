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

The runner checks that both applications exist and verifies total and distinct event counts (666,666 / 333,334), 256 exact users each, dimension cardinalities (4 names, 3 platforms, 5 countries), the exact compact generator properties string and timestamp bounds across all rows for each selected application. It rejects contaminated or incomplete fixtures. Seed is declared for existing data, not inferred from cardinalities. The runner records the actual ordered IDs, observed bounds, counts, software versions, host OS/CPU count/model/memory where available and Docker engine CPUs/memory and version. Missing metadata is null, not invented; the supplied Compose services have no explicit CPU/memory limits. The report describes the Docker engine resource pool, not per-query memory.

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

The local generation process includes different work from the earlier CI verification runner (which also checks stored IDs/dimensions). Neither result is an HTTP ingestion rate or a controlled hardware comparison. The benchmark preflight confirmed the local stored per-application distinct IDs, users, dimensions, expected generator properties and timestamp bounds. The original preflight used JSONExtract functions and failed on the older Intel Docker environment with simdjson UNSUPPORTED_ARCHITECTURE; commit `7eb86ea` uses a typed exact-string comparison for the generator’s deterministic compact JSON instead. This is deliberately specific to the synthetic fixture, not a general JSON equivalence test. The measured analytics SQL is unchanged.

## Query measurement evidence

Both runs succeeded on 2026-11-25. The [local report](benchmarks/local-2026-11-25.json) is the owner's original JSON from signed head `7eb86ea`. The independent [CI report](benchmarks/ci-45692040400.json) preserves the environment, fixture, typed queries and all raw numeric samples from [run 45692040400](https://github.com/szymoniwacz/pulselens/actions/runs/45692040400) (PR merge checkout `f21db74`). The checked-in CI report is a normalized reconstruction from the workflow JSON log; its result objects are identical to the local report as verified by the two recorded SHA-256 digests. The [original CI artifact](https://github.com/szymoniwacz/pulselens/actions/runs/45692040400/artifacts/15058214382) is available subject to GitHub retention.

Both environments used Ruby 3.4.13, Rails 8.1.4.1, PostgreSQL 17.12 and ClickHouse 26.8.46.6. Local host: MacBookPro11,5 (Intel, Darwin 21.6.0, 8 logical CPUs, 16 GiB RAM), Docker Engine 28.1.1 (8 CPUs, 8,220,098,560 bytes), Compose 2.35.1-desktop.1. CI: Linux 7.0.0-1020-azure on AMD EPYC 7763, 4 logical CPUs, 16,366,636 KiB reported host RAM, Docker Engine 29.4.2 (4 CPUs, 16,759,435,264 bytes), Compose 5.1.3. Server `max_threads` was auto(8) locally and auto(4) in CI; both measured requests explicitly disabled query and query-condition caches. These are not equivalent controlled hardware environments.

### Results

Each run verified the two selected applications contain exactly 666,666 and 333,334 events respectively, with the same distinct event ID counts per application, 256 unique users each, 4 names, 3 platforms, 5 countries and zero unexpected generator properties. Observed timestamp bounds matched across runs. Both runs returned 666,666 events / 256 unique users for the date-only shape and 19,186 / 256 for the dimension shape. Both 30-day series and top-event lists match, as evidenced by identical result SHA-256 values:

- Date only: `2296ae2efc1905e9436f9ca09b89edf6364eb857d69e9ab623461072587ce58f`
- Dimensions: `6b24f4f7b2287753d16ec7b7c0a7f278b87efcc9979c7486453879044`

The following times are milliseconds: first observed sample / median of samples 2–5. Read counts were constant across all five repetitions of each statement. Full samples, exact SQL and bound values are in the reports.

| Environment | Shape | Query | Server ms (first / median) | Client ms (first / median) | Rows read | Bytes read |
|---|---|---|---:|---:|---:|---:|

| Local | date_only | Totals | 23.49 / 28.08 | 27.57 / 32.70 | 680,512 | 29,680,451 |
| Local | date_only | Daily | 31.66 / 36.93 | 37.24 / 41.91 | 680,512 | 29,680,451 |
| Local | date_only | Top names | 20.95 / 22.24 | 26.39 / 27.09 | 680,512 | 24,208,307 |
| Local | dimensions | Totals | 25.80 / 28.35 | 32.49 / 33.72 | 680,512 | 38,917,597 |
| Local | dimensions | Daily | 29.25 / 28.69 | 39.19 / 34.98 | 680,512 | 38,917,597 |
| Local | dimensions | Top names | 20.49 / 21.94 | 27.13 / 28.73 | 680,512 | 25,569,434 |
| CI | date_only | Totals | 31.73 / 31.13 | 33.77 / 33.38 | 688,704 | 30,037,760 |
| CI | date_only | Daily | 41.58 / 38.09 | 44.18 / 40.33 | 688,704 | 30,037,760 |
| CI | date_only | Top names | 17.40 / 15.52 | 21.03 / 17.45 | 688,704 | 24,499,672 |
| CI | dimensions | Totals | 20.28 / 20.75 | 22.13 / 22.93 | 688,704 | 39,386,253 |
| CI | dimensions | Daily | 21.53 / 21.20 | 23.40 / 23.11 | 688,704 | 39,386,253 |
| CI | dimensions | Top names | 15.83 / 15.38 | 17.68 / 17.46 | 688,704 | 25,877,389 |

On the MacBook, summed client HTTP time for three sequential queries was 91.20–108.02 ms (date only) and 95.31–111.98 ms (dimensions). This excludes authentication, JSON parsing, Rails processing and HTML rendering; it is not end-to-end dashboard latency. Adding dimensions reduced matching events but did not reduce rows read in this full-month sample, and increased bytes read because additional columns were needed. Read rows exceed matching rows because the storage engine reads granules; different runs may have different part layouts. The measurements demonstrate reproducibility of the aggregate values, not invariant latency or a performance guarantee. No cache was flushed; first observed does not mean cold.
