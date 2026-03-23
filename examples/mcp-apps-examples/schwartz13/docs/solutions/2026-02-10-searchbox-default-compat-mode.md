---
title: "Default Compat Mode with Strict Override"
category: design
tags: [manage_websets, compat-mode, configuration]
created: 2026-02-10
related_plan: docs/plans/2026-02-10-task-searchbox-7g3-default-compat-mode-plan.md
related_issue: searchbox-7g3
related_pr: pending
---

# Default Compat Mode with Strict Override

## Problem
`manage_websets` safe coercion required per-call `args.compat.mode = "safe"`. This was explicit but repetitive for deployments that want safe coercion behavior broadly.

## Impact
- User impact: medium (repeated caller boilerplate in safe-mode deployments)
- System impact: low (configuration and dispatch-layer behavior only)
- Scope: server startup config, dispatcher/coercion precedence, docs, tests

## Root Cause
Compatibility mode existed only at request scope. There was no server-level default setting to express deployment policy.

## Solution
Added server-level default compat mode with strict baseline and explicit precedence:

- New env/config:
  - `MANAGE_WEBSETS_DEFAULT_COMPAT_MODE` (`strict` default, `safe` optional)
- Precedence:
  - Per-call `args.compat.mode` overrides server default
  - `args.compat.mode = "strict"` forces strict validation even when server default is `safe`
- Invalid mode handling:
  - Invalid env value falls back to strict with warning
  - Invalid per-call mode is ignored with warning and coerces to strict behavior

### Files Changed
- `src/tools/coercion.ts`
- `src/tools/manageWebsets.ts`
- `src/server.ts`
- `src/index.ts`
- `src/tools/__tests__/coercion.test.ts`
- `src/tools/__tests__/manageWebsets.test.ts`
- `README.md`
- `TOOL_SCHEMAS.md`
- `CLAUDE.md`
- `docs/plans/2026-02-10-task-searchbox-7g3-default-compat-mode-plan.md`

### Validation
- `npm run build` -> pass
- `npx vitest run src/tools/__tests__/coercion.test.ts src/tools/__tests__/manageWebsets.test.ts` -> pass
- `npm run test:unit` -> pass

## Prevention
- Keep strict as global default.
- Require explicit opt-in for safe coercion.
- Always expose warnings for invalid mode inputs.
- Keep precedence rules documented and tested.

## Reusable Pattern
When introducing global defaults for behavior changes, preserve strict baseline and add per-request explicit override (`strict`) to prevent policy lock-in.

## Follow-Ups
- [ ] Evaluate whether CLI/docs should include a deployment profile section with recommended env defaults.
