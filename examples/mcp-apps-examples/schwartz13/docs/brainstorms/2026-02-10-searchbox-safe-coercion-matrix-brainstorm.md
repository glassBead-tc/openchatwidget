---
date: 2026-02-10
topic: searchbox-safe-coercion-matrix
---

# Searchbox Safe Coercion Matrix

## What We're Building
Define a safe, explicit coercion policy for `manage_websets` that improves agent success rates on common input-shape mistakes without weakening correctness.

The target users are agent callers directly using `manage_websets` and workflow builders using `tasks.create`. The primary usability problem is repeated schema footguns (`entity`, `criteria`, `options`, argument shape), plus avoidable failures from strict type mismatches that are deterministic to repair.

The output of this brainstorm is a coercion matrix that classifies each input family as:
- `Auto-coerce` (safe and deterministic)
- `Reject with guidance` (ambiguous or high-risk)
- `Pass-through` (already robust or low value to coerce)

## Why This Approach
We considered three approaches:

### Approach A: Strict-First (No Coercion)
Keep behavior strict and only improve errors/docs.
Pros: predictable semantics, low maintenance.
Cons: repeated agent failures on known, low-risk formatting mistakes.

### Approach B: Forgiving-First (Always Coerce)
Auto-repair most malformed inputs.
Pros: high short-term success rate.
Cons: silent semantic drift, harder debugging, higher long-term maintenance risk.

### Approach C: Hybrid (Recommended)
Strict by default, with explicit opt-in coercion mode and transparent coercion reporting.
Pros: preserves correctness baseline while improving agent ergonomics where safe.
Cons: slightly more surface area than strict-only.

Recommendation: **Approach C**. It aligns with reliability goals while still reducing high-frequency agent errors.

## Safe Coercion Matrix

| Input family | Example bad input | Decision | Notes |
|---|---|---|---|
| `entity` object shape | `"company"` | Auto-coerce | Coerce to `{ "type": "company" }` when value is a known entity type string. |
| `criteria` shape | `["has funding"]` | Auto-coerce | Coerce to `[{"description":"has funding"}]` for arrays of non-empty strings. |
| `options` shape | `["Seed","Series A"]` | Auto-coerce | Coerce to `[{"label":"Seed"},{"label":"Series A"}]` for arrays of non-empty strings. |
| Numeric fields | `"25"` | Auto-coerce | Only for known numeric fields; must parse cleanly and satisfy bounds. |
| Boolean fields | `"true"` / `"false"` | Auto-coerce | Only for known boolean fields. |
| `tasks.create` argument placement | top-level workflow args instead of nested `args` | Pass-through | Already tolerated; keep as-is and document as compatibility behavior. |
| Enum normalization | `"Append"` vs `"append"` | Reject with guidance | Case coercion can mask intent; return clear allowed values. |
| Cron expressions | malformed cron | Reject with guidance | Too ambiguous/risky to auto-fix; keep explicit validation. |
| Date/time fields | partial or non-ISO date strings | Reject with guidance | Avoid timezone/format ambiguity. |
| Nested complex objects | malformed `researchSchema`, complex `contents` objects | Reject with guidance | Preserve explicit contract and avoid structural guesses. |

## Key Decisions
- Use **hybrid mode**: strict default, coercion opt-in.
- Coerce only **deterministic, lossless, high-frequency** mistakes.
- Return visible coercion metadata in responses (`_coercions`, `_warnings`) when coercion occurs.
- Never coerce ambiguous inputs (cron, dates, enums, complex nested structures).

## Open Questions
- What should the opt-in flag be (`compat`, `coercionMode`, or another name)?
- Should coercion be enabled per-call only, or also support server-level default config?
- Should we add a `dry_run_coercions` mode that reports proposed repairs without applying them?

## Next Steps
Move this into implementation planning via the compound workflow and define:
- Final coercion contract
- Allowed field-path whitelist
- Warning/metadata response format
