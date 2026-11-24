# Glossary

| Term | Meaning |
|---|---|
| Application | Demo event producer and isolation boundary; proposed PostgreSQL record with UUID and API key digest. |
| API key | Bearer credential shown once at creation; only its digest is stored. |
| Event | Synthetic activity record; client event_id is an identifier, not a deduplication guarantee. |
| occurred_at | Client timestamp with timezone, normalized to UTC; drives filters, partitioning proposal and daily grouping. |
| received_at | UTC timestamp assigned by the server. |
| Unique user | Distinct synthetic user_id within the authenticated application and query range. |
| Daily active users | Exact distinct users within a UTC day; these counts must not be summed to produce range uniques. |
| Half-open range | from ≤ occurred_at < to. |
| Unknown write outcome | A failed/lost response may follow a successful insert; retries can increase counters. |
| Reproducible dataset | Same seed, parameters and documented generator version produce the same logical events; database timings can vary. |
| Readiness | Separate bootstrap gate; definition coverage alone does not authorize product implementation. |
