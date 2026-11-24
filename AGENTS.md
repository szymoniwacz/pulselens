# Agent Instructions

## Repository role

PulseLens is an event analytics application supporting local operation with synthetic data. Its approved stack is a Rails API and server-rendered dashboard, PostgreSQL application metadata/API authentication, ClickHouse event analytics, Docker Compose and RSpec.

This branch contains project definition and readiness-safe bootstrap only; no Rails product code exists yet. Product setup/run/test/build/lint/typecheck commands and service-backed CI are explicitly deferred to scaffold issue #3. Do not substitute commands from reusable profile examples.

Read `.ai/project/product-context.md`, `.ai/project/scope.md` and `.ai/docs/project-requirements.md` for product boundaries, approved decisions, the active Rails profile and readiness evidence. Review and merge remain with the owner. A completed definition or readiness check does not authorize product implementation by itself.

## Workflow entry point

This repository uses a private reusable AI workflow through the `.ai-template` submodule.

If `.ai/README.md` is not available, run `./scripts/setup-ai-workflow.sh` first. If the private workflow cannot be loaded, stop rather than inventing replacement workflow rules.

After setup, `.ai/` is the source of truth for workflow, policies, skills, review rules, Git rules, and automation instructions.

Read `.ai/README.md` first. For end-to-end goals follow `.ai/skills/execute-goal.md`.

Project-specific context is tracked in `.ai/` as an overlay and must not be overwritten by reusable workflow updates.
