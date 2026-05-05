# FitForge Docs

This directory holds repository-grounded documentation for the current Flutter app.

- [architecture.md](architecture.md) — app structure, state flow, persistence, and module boundaries
- [testing.md](testing.md) — local test commands, current suite coverage, and planned gaps
- [release.md](release.md) — versioning rules, Android tag releases, and web deployment flow
- [privacy.md](privacy.md) — local data handling, export/import behavior, and safety notice
- [agent_mvp_status.md](agent_mvp_status.md) — Coach Agent MVP stability snapshot (current tag `agent-mvp-eval-v2`), eval status, runtime modes, and next-stage roadmap
- [coach_agent_evals.md](coach_agent_evals.md) — eval suite contract, case categories, status meanings, and how to add a case
- [generate_plan_agent_boundary.md](generate_plan_agent_boundary.md) — generatePlan product boundary: LLM is a router, not a plan generator

If the code and docs disagree, the code in `lib/`, `test/`, and `.github/workflows/` is the source of truth and the docs should be updated.
