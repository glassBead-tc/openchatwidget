---
title: feat: Safe Coercion Compatibility Mode for manage_websets
type: feat
date: 2026-02-10
---

# feat: Safe Coercion Compatibility Mode for manage_websets

## Overview
Add a strict-default, opt-in compatibility coercion mode for `manage_websets` that auto-repairs a small set of deterministic input-shape mistakes and reports applied coercions in the response.

## Problem Statement / Motivation
Agent callers repeatedly fail on known formatting footguns (`entity`, `criteria`, `options`, basic scalar types). Current strict validation is correct but causes avoidable retries and context churn. A narrow, transparent coercion layer can improve first-try success without introducing ambiguous behavior.

## Scope
- In scope:
  - Add opt-in coercion mode for safe, deterministic repairs.
  - Implement coercion metadata reporting (`_coercions`, `_warnings`) in successful responses.
  - Keep ambiguous/high-risk inputs strict with current error guidance.
  - Add tests for coercion and non-coercion behavior.
- Out of scope:
  - Coercion of cron/date/complex nested schema structures.
  - Broad semantic normalization (enum case-fixing, fuzzy matching).
  - Any default-on coercion behavior.

## Stakeholders
- End users: indirect benefit via fewer failed agent calls and faster results.
- Contributors: clearer compatibility behavior and test coverage for accepted coercions.
- Operations/maintainers: preserve strict contracts by default while reducing repetitive support/debug cycles.

## Proposed Solution
Introduce an opt-in compatibility envelope:
- `args.compat.mode = "safe"` enables safe coercions.
- Coercions applied pre-dispatch to handler args.
- Coercion decisions come from an explicit field-path whitelist and are never ambiguous.

Initial safe coercions:
- `entity`: `"company"` -> `{ "type": "company" }` (known entity string only)
- `criteria`: `["x"]` -> `[{"description":"x"}]`
- `options`: `["A"]` -> `[{"label":"A"}]`
- Selected numeric fields: clean numeric strings -> numbers
- Selected boolean fields: `"true"`/`"false"` -> booleans

Response metadata:
- `_coercions`: array of `{ path, from, to }` (summarized values)
- `_warnings`: array of human-readable notes

## Technical Considerations
- Architecture impacts:
  - Add coercion module in tool dispatch layer (`manage_websets`) without altering handler contracts.
  - Keep compatibility logic centralized and testable.
- Performance implications:
  - Minimal overhead from shallow object transforms.
- Security considerations:
  - Strict-default behavior retained.
  - No coercion for ambiguous or high-risk fields.

## Risk Tier
- Tier: `R1`
- Rationale: Behavioral code-path changes across request input handling, but with constrained scope, explicit opt-in, and comprehensive tests.

## Acceptance Criteria
- [ ] `manage_websets` supports opt-in `compat.mode = "safe"` coercion behavior.
- [ ] Safe coercions are implemented for `entity`, `criteria`, `options`, and whitelisted numeric/boolean fields.
- [ ] Coercion metadata is returned in successful responses when coercions occur.
- [ ] Without compat mode, existing strict behavior remains unchanged.
- [ ] Ambiguous inputs (cron/date/complex nested structures) are not coerced.
- [ ] Tests cover coercion success, strict-mode behavior, and rejection boundaries.

## Validation Plan
- Build/type checks:
  - `npm run build`
- Tests:
  - `npm run test`
- Additional checks:
  - `npx vitest run src/handlers/__tests__/ src/workflows/__tests__/ src/tools/__tests__/manageWebsets*.test.ts`

## Dependencies & Risks
- Dependencies:
  - Existing handler validation behavior and tests.
  - Stability of operation names and argument shapes in dispatcher.
- Risks:
  - Silent behavior changes if coercion leaks outside compat mode.
  - Over-coercion if whitelist is too broad.
- Mitigations:
  - Gate all coercion behind explicit compat flag.
  - Keep whitelist narrow and test every coercion rule.
  - Include coercion metadata for traceability.

## Implementation Plan
### Phase 1
- [ ] Add coercion module with whitelist-driven rules and metadata.
- [ ] Integrate module into `manage_websets` dispatch flow.

### Phase 2
- [ ] Add/extend tests for opt-in coercion and strict-mode parity.
- [ ] Validate ambiguous fields remain strict.

### Phase 3
- [ ] Update user-facing docs with compat-mode examples and boundaries.
- [ ] Run build/tests and address any regressions.

## Rollback Strategy
Disable coercion path by removing/ignoring `compat.mode` handling. Since strict mode remains baseline, rollback is low-risk and does not require data migration.

## Compound Plan
What to capture post-implementation:
- Note path target: `docs/solutions/2026-02-10-searchbox-safe-coercion.md`
- Expected reusable lessons:
  - How to add compatibility behavior without changing core handler contracts.
  - How to design safe coercion boundaries for agent-facing APIs.

## References
- Internal:
  - `docs/brainstorms/2026-02-10-searchbox-safe-coercion-matrix-brainstorm.md`
  - `docs/workflows/compound-engineering-workflow.md`
  - `src/tools/manageWebsets.ts`
  - `src/handlers/types.ts`
