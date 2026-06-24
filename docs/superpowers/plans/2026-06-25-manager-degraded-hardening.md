# Manager Degraded Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish manager/engine hardening by making failed engine starts observable as degraded state with backoff and explicit restart timeout handling.

**Architecture:** Keep the manager VM source-only. Track degraded root state inside `PhoenixLS.Project.Manager`, emit telemetry through `PhoenixLS.Support.Telemetry`, and keep timeout/backoff behavior deterministic and testable.

**Tech Stack:** Elixir, ExUnit, OTP Registry/DynamicSupervisor, existing `EngineStatus`, existing telemetry wrapper.

---

## Tasks

- [x] **Step 1: Write failing tests**

Add tests proving:
- failed engine start records degraded status, emits `[:phoenix_ls, :project, :degraded]`, and backs off immediate retry
- restart returns a timeout error if an engine registry entry cannot unregister within the configured timeout

- [x] **Step 2: Verify RED**

Run:

```bash
cd server && mix test apps/phoenix_ls/test/phoenix_ls/project/engine_status_test.exs
```

- [x] **Step 3: Implement manager hardening**

Add manager state for degraded roots and backoff deadlines. Emit telemetry on degraded transitions. Make `restart_engine/2` respect a configurable unregister timeout.

- [x] **Step 4: Verify GREEN**

Run the focused command again. Expected: PASS.

- [x] **Step 5: Full verification and commit**

Run format, full tests, warnings-as-errors compile, regex scan, diff checks, then commit:

```bash
git commit -m "feat: harden manager degraded state handling"
```

## Self-Review

- Spec coverage: Completes the remaining backoff, timeout, and degraded telemetry parts of the core hardening objective.
- Placeholder scan: No TBD/TODO/fill-in steps.
- Type consistency: Manager APIs keep existing return shapes plus explicit error tuples for backoff/timeout.
