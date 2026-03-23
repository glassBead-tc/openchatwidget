---
title: "Safe Coercion Mode for Agent Input Footguns"
category: design
tags: [manage_websets, compatibility, agent-ux]
created: 2026-02-10
related_plan: docs/plans/2026-02-10-feat-searchbox-safe-coercion-plan.md
related_issue: searchbox-der
related_pr: pending
---

# Safe Coercion Mode for Agent Input Footguns

## Problem
Agent callers repeatedly sent known malformed input shapes (`entity`, `criteria`, `options`, numeric/boolean strings), causing avoidable retries and strict validation failures.

## Impact
- User impact: medium (higher retry loops and lower first-try success for agent calls)
- System impact: low (contract already strict and deterministic)
- Scope: `src/tools/manageWebsets.ts`, docs, and new coercion tests

## Root Cause
The API contract is strict by design, but common agent mistakes are highly repetitive and deterministic to repair. There was no compatibility layer for low-risk repairs, so all mistakes incurred full failure/retry cycles.

## Solution
Implemented opt-in compatibility coercions behind `args.compat.mode = "safe"`:
- Added coercion engine in `src/tools/coercion.ts`
- Integrated coercion pre-dispatch in `src/tools/manageWebsets.ts`
- Added response metadata (`_coercions`, `_warnings`) for transparency
- Kept strict-default behavior unchanged
- Documented contract and boundaries in `README.md` and `TOOL_SCHEMAS.md`

### Files Changed
- `src/tools/coercion.ts`
- `src/tools/manageWebsets.ts`
- `src/tools/__tests__/coercion.test.ts`
- `src/tools/__tests__/manageWebsets.test.ts`
- `README.md`
- `TOOL_SCHEMAS.md`
- `docs/plans/2026-02-10-feat-searchbox-safe-coercion-plan.md`
- `docs/brainstorms/2026-02-10-searchbox-safe-coercion-matrix-brainstorm.md`

### Validation
- `npm run build` -> pass
- `npm run test` -> fail in sandbox (network/Docker integration constraints, unrelated to coercion changes)
- Additional checks:
  - `npx vitest run src/tools/__tests__/coercion.test.ts src/tools/__tests__/manageWebsets.test.ts` -> pass
  - `npm run test:unit` -> pass

## Prevention
- Keep compatibility behavior opt-in and narrow.
- Never coerce ambiguous fields (cron/date/enum case/complex schemas).
- Require explicit metadata for every applied coercion.
- Add tests for each new coercion rule before enabling it.

## Reusable Pattern
For agent-facing APIs: use strict-default contracts plus explicit, transparent compatibility mode for deterministic repairs. Centralize repair logic in one pre-dispatch layer and keep handler contracts unchanged.

## Follow-Ups
- [ ] Decide whether to support server-level default compat mode in addition to per-call mode.
- [ ] Add a `dry_run_coercions` option to preview repairs without applying them.
