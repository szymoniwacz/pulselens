# Roadmap

Source: [definition issue #1](https://github.com/szymoniwacz/pulselens/issues/1). Requirements: [definition-4](../docs/project-requirements.md). Issues below are a prepared backlog, not execution authorization. No product work has started.

## Current — definition and readiness

Project definition coverage and A-01–A-09 owner approvals are complete (D-004–D-014). Versions/client/timeouts/sorting remain delegated to #3/#5/#7. Product start is still BLOCKED: #2 must finish product README/AGENTS customization and pass readiness; PR #12 remains for owner review/merge. No implementation or merge is authorized by this documentation request. See the requirements readiness assessment for evidence.

| Order | Goal | Issue | Blocked by | Requirements |
|---|---|---|---|---|
| 0 | Confirm decisions and project readiness; no product behavior | [#2](https://github.com/szymoniwacz/pulselens/issues/2) | Definition #1 reviewed and available | Definition/readiness contract |
| 1 | Rails scaffold, local dependencies and initial service-backed CI | [#3](https://github.com/szymoniwacz/pulselens/issues/3) | #2 | FR-010/011/012 |
| 2 | Application creation and API key authentication | [#4](https://github.com/szymoniwacz/pulselens/issues/4) | #3 | FR-001 |
| 3 | Versioned ClickHouse schema and client | [#5](https://github.com/szymoniwacz/pulselens/issues/5) | #3 | FR-002/010 |
| 4 | Validated HTTP batch ingestion | [#6](https://github.com/szymoniwacz/pulselens/issues/6) | #4, #5 | FR-003/004/005 |
| 5 | Exact analytics service and API | [#7](https://github.com/szymoniwacz/pulselens/issues/7) | #4, #5 | FR-006/007 |
| 6 | Local server-rendered dashboard | [#8](https://github.com/szymoniwacz/pulselens/issues/8) | #7 | FR-008 |
| 7 | Reproducible bounded-memory generator | [#9](https://github.com/szymoniwacz/pulselens/issues/9) | #4, #5 | FR-009 |
| 8 | Cross-system integration and CI gap closure | [#10](https://github.com/szymoniwacz/pulselens/issues/10) | #6, #7, #8, #9 | FR-011; FR-001–010 integration |
| 9 | Final architecture documentation and 1M-event measurements | [#11](https://github.com/szymoniwacz/pulselens/issues/11) | #10 | FR-012/013 |

Dependencies are prerequisites, not merely a display order. Verify actual implementation on the target branch before dependent execution. Every issue has acceptance criteria, scope, exclusions, risks/decision queue and verification. Tests and incremental documentation ship with each feature; #10/#11 close cross-system and final evidence gaps.

## Phases and exit evidence

1. **Readiness and scaffold (#2–3):** confirmed project gate, real runnable scaffold, recorded commands and initial CI. Readiness may defer missing commands to #3 under the greenfield exception.
2. **First useful vertical slice (#4–7):** create key → HTTP ingestion → real ClickHouse → correct authenticated analytics. Auth/schema can be planned independently after #3; analytics does not depend on the HTTP ingestion implementation.
3. **Demo experience (#8–9):** dashboard and deterministic multi-application generation. Generator uses the shared adapter and need not depend on ingestion or dashboard.
4. **MVP evidence (#10–11):** cross-system tests green in CI, clean-checkout walkthrough and reproducible one-million-event query measurements.

## Planning audit — 2026-11-24

- Default branch main verified through GitHub: `3d429c5097b77606b95a6fd3421222e9010cdf23`; local HEAD/tree matched. Definition input: issue #1, no comments. Requirements revision: definition-1.
- Evidence: tree has adapter scripts, fixture tests and adapter CI; no Gemfile, app/, db/ or spec/ product files. Existing README describes the adapter. No earlier implementation issues or open/closed PRs found. Duplicate checks repeated immediately before each issue creation.
- Coverage: FR-001–013 product outcomes **MISSING**, confirmed from tree inspection; feature tests and product CI **MISSING**, not inferred from an unavailable run. Readiness **PARTIAL**: workflow exists, product customization and confirmations pending. Existing adapter CI is not product evidence.
- Scope exclusions are **DEFERRED** beyond this MVP; no implementation drift is claimed because no product implementation exists. Performance/runtime behavior is unmeasured, not a passing result.
- Backlog follows confirmed desired outcomes; unapproved implementation choices stay in decision queues. Interactive issue creation is explicitly authorized; controlled autonomy configuration is unchanged. No Project Executor delegation marker or authorization was posted.
- Recommendation: **OWNER_DECISION** for readiness #2. It is the next safe bounded goal once definition is reviewed and execution is separately authorized. No product goal is currently implementation-ready.

## Deferred

Out-of-scope ideas are not delivery commitments. Revisit only with a new approved scope. See [scope](scope.md). Complete template customization and the project readiness gate before starting product delivery.
