---
title: "Fix coercion/validation regressions in manage_websets"
category: debugging
tags: [mcp, validation, compatibility, coercion]
created: 2026-02-10
related_plan: docs/plans/2026-02-10-task-searchbox-zu4-dry-run-coercion-plan.md
related_issue: searchbox-zu4
related_pr: n/a
---

# Fix coercion/validation regressions in manage_websets

## Problem
Recent dispatcher changes introduced regressions:
- Safe compat coercions were blocked by strict schema validation running first.
- Legacy caller shape (`{ operation, args: {...} }`) stopped working.
- `websets.create` enrichment `options` were stripped by schema parsing.

## Impact
- User impact: medium
- System impact: medium
- Scope: `src/tools/manageWebsets.ts`, `src/handlers/websets.ts`, `src/tools/__tests__/manageWebsets.test.ts`

## Root Cause
Validation was moved to a strict discriminated-union input schema at tool registration time, which executed before coercion and before legacy-shape normalization. Also, `websets.Schemas.create` omitted `enrichments[].options`.

## Solution
- Switched tool input schema back to permissive envelope (`operation` + optional legacy `args` + catchall).
- Normalized both input shapes in dispatcher (`top-level` preferred, legacy `args` supported).
- Applied compat coercions first, then ran operation-specific schema validation in dispatcher.
- Kept dry-run preview behavior after successful validation.
- Added `enrichments[].options` to `websets.create` schema.
- Added regression tests covering:
  - safe coercion with legacy args
  - strict-mode validation behavior
  - legacy args compatibility
  - preview behavior
  - enrichment options preservation

### Files Changed
- `src/tools/manageWebsets.ts`
- `src/handlers/websets.ts`
- `src/tools/__tests__/manageWebsets.test.ts`
- `docs/plans/2026-02-10-task-searchbox-zu4-dry-run-coercion-plan.md`

### Validation
- `npm run build` -> pass
- `npm run test` -> fail (expected in sandbox: external API DNS, Docker/e2e environment)
- Additional checks -> `npx vitest run src/tools/__tests__/coercion.test.ts src/tools/__tests__/manageWebsets.test.ts src/handlers/__tests__/registry.test.ts src/handlers/__tests__/tasks.test.ts src/handlers/__tests__/exa.test.ts src/handlers/__tests__/monitors.test.ts src/handlers/__tests__/enrichments.test.ts` pass

## Prevention
- Keep input transport parsing permissive when compatibility coercions are a supported feature.
- Perform operation schema validation after normalization/coercion in dispatcher.
- Add regression tests that execute through registered tool schema + handler, not handler alone.

## Reusable Pattern
When supporting migration paths (`legacy shape` + `new shape`), normalize first, coerce second, validate third, execute last.

## Follow-Ups
- [ ] Add integration coverage for legacy `args` envelope in transport-level tests.
- [ ] Document strict-vs-safe validation order in `README.md` and `TOOL_SCHEMAS.md` examples.
