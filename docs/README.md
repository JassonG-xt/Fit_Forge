# FitForge Docs

This directory holds repository-grounded documentation for the current Flutter app.

- [architecture.md](architecture.md) — app structure, state flow, persistence, and module boundaries
- [testing.md](testing.md) — local test commands, current suite coverage, and planned gaps
- [release.md](release.md) — versioning rules, Android tag releases, and web deployment flow
- [privacy.md](privacy.md) — local data handling, export/import behavior, and safety notice
- [agent_capabilities.md](agent_capabilities.md) — Coach Agent capabilities map: supported modes, supported actions table (mutation vs read-only), safety model, privacy model, current limitations, and explicit out-of-scope list
- [agent_mvp_status.md](agent_mvp_status.md) — Coach Agent MVP stability snapshot (current tag `agent-mvp-eval-v2`), eval status, runtime modes, and next-stage roadmap
- [coach_agent_evals.md](coach_agent_evals.md) — eval suite contract, case categories, status meanings, and how to add a case
- [agent_architecture_diagram.md](agent_architecture_diagram.md) — Mermaid diagrams for high-level data flow, mutation safety boundary (backend / Flutter swimlanes), safety short-circuit, generatePlan boundary, and eval/CI boundary
- [coach_agent_demo_script.md](coach_agent_demo_script.md) — short showcase / recording demo script (4 core scenarios: reschedule / replace / compress / safety)
- [agent_demo_script.md](agent_demo_script.md) — longer Coach Agent eval walkthrough (5–8 minute walkthrough covering reschedule / compress / clarification / replace / safety / generatePlan)
- [agent_demo_recording_checklist.md](agent_demo_recording_checklist.md) — recording-time execution checklist for the demo script: privacy checks, environment options, ordered flow, things to say / not say, post-recording review
- [release_notes_agent_mvp_eval_v2.md](release_notes_agent_mvp_eval_v2.md) — `agent-mvp-eval-v2` release notes: included capabilities, intentional non-goals, eval status, safety model, and known limitations
- [generate_plan_agent_boundary.md](generate_plan_agent_boundary.md) — generatePlan product boundary: LLM is a router, not a plan generator

If the code and docs disagree, the code in `lib/`, `test/`, and `.github/workflows/` is the source of truth and the docs should be updated.
