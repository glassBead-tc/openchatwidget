---
title: task: Evaluate and Add Server-Level Default Compat Mode
type: task
date: 2026-02-10
---

# task: Evaluate and Add Server-Level Default Compat Mode

## Overview
Decide and implement policy for whether safe coercion should remain per-call only or support a server-level default configuration.

## Problem Statement / Motivation
Per-call `compat.mode = "safe"` is explicit but repetitive for agent callers. Some deployments may want safe coercion enabled by default for all calls, while still preserving strict behavior as the global default and allowing explicit per-call override.

## Scope
- In scope:
  - Add optional server-level default compat mode configuration.
  - Preserve strict default behavior unless explicitly configured.
  - Support per-call override behavior.
  - Update docs and tests.
- Out of scope:
  - New coercion rules.
  - Non-safe coercion modes.

## Stakeholders
- End users: faster first-try success in deployments opting into default safe mode.
- Contributors: clearer compatibility behavior with explicit precedence rules.
- Maintainers: retain strict baseline and explicit override path.

## Proposed Solution
Decision: support server-level default mode with strict baseline.

Policy:
- Global default remains strict.
- New server config/env can set default mode to `safe`.
- Per-call `args.compat.mode` takes precedence over server default.
- Add explicit per-call `compat.mode = "strict"` to force strict behavior when server default is safe.

Planned config:
- Environment variable: `MANAGE_WEBSETS_DEFAULT_COMPAT_MODE` with allowed values `safe` or `strict`.

## Technical Considerations
- Architecture impacts:
  - Thread default mode from `index.ts` -> `createServer` -> `registerManageWebsetsTool` -> coercion resolver.
- Performance implications:
  - Negligible.
- Security considerations:
  - Strict remains default.
  - Invalid mode values degrade to strict and emit warnings.

## Risk Tier
- Tier: `R1`
- Rationale: small behavioral change in request handling with testable boundaries.

## Acceptance Criteria
- [ ] Server-level default compat mode is configurable and defaults to strict.
- [ ] Per-call mode overrides server-level mode.
- [ ] `compat.mode = "strict"` forces strict behavior.
- [ ] Invalid default/per-call modes do not enable coercion.
- [ ] Docs include default mode config and precedence.
- [ ] Tests cover default mode, strict override, and invalid mode behavior.

## Validation Plan
- Build/type checks:
  - `npm run build`
- Tests:
  - `npx vitest run src/tools/__tests__/coercion.test.ts src/tools/__tests__/manageWebsets.test.ts`
  - `npm run test:unit`
- Additional checks:
  - manual `manage_websets` calls with and without `compat`.

## Dependencies & Risks
- Dependencies:
  - Existing coercion module and dispatcher integration.
- Risks:
  - Accidental default-on behavior in environments not expecting it.
  - Confusing precedence between global and per-call settings.
- Mitigations:
  - Keep strict default.
  - Document precedence clearly.
  - Test all precedence branches.

## Implementation Plan
### Phase 1
- [ ] Extend coercion resolver to accept default mode and strict override.
- [ ] Thread default mode through server setup and tool registration.

### Phase 2
- [ ] Update tests for precedence and strict override behavior.
- [ ] Update README and TOOL_SCHEMAS docs.

### Phase 3
- [ ] Run validations.
- [ ] Capture compound note with decision rationale.

## Rollback Strategy
Set default mode to strict (or remove env var) and retain per-call explicit behavior. If needed, revert default mode wiring while keeping existing per-call compatibility.

## Compound Plan
What to capture:
- How to add configurable behavior without changing strict baseline.
- Precedence design pattern for global defaults vs per-request overrides.

## References
- `docs/solutions/2026-02-10-searchbox-safe-coercion.md`
- `src/tools/coercion.ts`
- `src/tools/manageWebsets.ts`
- `src/server.ts`
- `src/index.ts`
