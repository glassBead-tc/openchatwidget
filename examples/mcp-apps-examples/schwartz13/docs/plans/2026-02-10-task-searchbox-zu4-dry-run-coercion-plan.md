---
title: task: Add Dry-Run Coercion Preview Mode
type: task
date: 2026-02-10
---

# task: Add Dry-Run Coercion Preview Mode

## Overview
Add a dry-run path to preview coercions without executing the selected `manage_websets` operation.

## Problem Statement / Motivation
Callers currently discover coercion effects only after execution. For safety-sensitive workflows, agents need a "show me what will be repaired" mode before invoking external API calls.

## Scope
- In scope:
  - Add per-call preview flag in `compat`.
  - Return normalized args and coercion metadata without executing handlers.
  - Document behavior and precedence with default/per-call mode.
  - Add tests for preview behavior.
- Out of scope:
  - New coercion rules.
  - Changes to handler-level validation behavior.

## Stakeholders
- End users: safer agent operations through preflight visibility.
- Contributors: clearer debugging and reproducible coercion behavior.
- Maintainers: reduced unnecessary outbound calls during troubleshooting.

## Proposed Solution
Use `args.compat.preview = true`:
- Coercion pipeline still runs.
- Handler execution is skipped.
- Response returns preview payload with:
  - operation
  - effective mode
  - normalized args
  - execution skipped indicator
- Existing `_coercions` / `_warnings` metadata remains attached.

## Technical Considerations
- Architecture impacts:
  - Small dispatch-layer branch in `manageWebsets`.
  - Extend coercion result shape to include preview/effective mode.
- Performance implications:
  - Reduced cost in preview mode since handlers are not called.
- Security considerations:
  - No additional permissions; fewer side effects due to no execution.

## Risk Tier
- Tier: `R1`
- Rationale: request behavior branching in dispatcher with manageable blast radius and unit-test coverage.

## Acceptance Criteria
- [x] `compat.preview = true` returns coercion preview and skips handler execution.
- [x] Preview respects default compat mode and per-call mode override.
- [x] `_coercions`/`_warnings` remain visible in preview responses.
- [x] Unknown operation behavior unchanged (still errors).
- [x] Docs include preview usage examples.
- [x] Tests verify no handler call in preview mode.
- [x] Safe coercion remains usable with schema validation (validation now runs after coercion).
- [x] Legacy `args` envelope remains supported for backward compatibility.
- [x] `websets.create` preserves enrichment `options` payloads.

## Validation Plan
- `npm run build`
- `npx vitest run src/tools/__tests__/coercion.test.ts src/tools/__tests__/manageWebsets.test.ts`
- `npm run test:unit`

## Dependencies & Risks
- Dependencies:
  - Existing compat coercion module and metadata plumbing.
- Risks:
  - Misunderstanding preview as execution.
- Mitigations:
  - Explicit response fields indicating execution skipped.
  - Doc examples clarifying semantics.

## Implementation Plan
### Phase 1
- [x] Extend coercion result model for preview/effective mode.
- [x] Add preview branch in `manage_websets` dispatch.

### Phase 2
- [x] Add tests for preview semantics and handler skip.
- [x] Update README/TOOL_SCHEMAS/description text.
- [x] Add regression tests for safe-coercion + legacy args compatibility.
- [x] Add regression test for `websets.create` enrichment options preservation.

### Phase 3
- [x] Run validations.
- [x] Capture compound note.

## Rollback Strategy
Remove preview branch and revert to current execution-only behavior while keeping coercion features intact.

## References
- `src/tools/coercion.ts`
- `src/tools/manageWebsets.ts`
- `docs/solutions/2026-02-10-searchbox-safe-coercion.md`
- `docs/solutions/2026-02-10-searchbox-default-compat-mode.md`
