---
title: "refactor: Agent-native improvements for schwartz13 MCP server"
type: refactor
status: completed
date: 2026-03-23
---

# Agent-Native Improvements for schwartz13 MCP Server

## Enhancement Summary

**Deepened on:** 2026-03-23
**Research agents used:** 12 (Code Mode skill, agent-native skill, learnings analysis, architecture strategist, security sentinel, performance oracle, code simplicity reviewer, agent-native reviewer, TypeScript reviewer, pattern recognition specialist, MCP best practices researcher, MCP SDK docs researcher)

### Key Improvements from Deepening
1. **Consolidated from 5 phases to 3** — cut Phase 4 (MCP resource duplicates status tool), merged Phases 1+2 (both modify dispatch path)
2. **Simplified module extraction** — rename `manageWebsets.ts` to `operations.ts` instead of creating a new file alongside the old one
3. **Inline error hints** — 5 lines in the existing file instead of a new `errorHints.ts` module
4. **Security hardening** — remove raw `exa` SDK from sandbox context; audit `BOOLEAN_FIELDS` for name collisions
5. **Performance** — TTL cache + timeout on status aggregation; use `Promise.allSettled` for graceful degradation
6. **Richer status response** — recent webset summaries, active task details, capabilities field, `hasMore` pagination flag
7. **Fixed factual errors** — `by_status` keys now match actual `Webset['status']` union; Exa pagination has no `total` field

### New Considerations Discovered
- Phase 1 reverses the documented strict-by-default principle (Learning 2) — justified by agent-native context but needs explicit documentation
- `text` field in `BOOLEAN_FIELDS` risks silent type confusion when safe mode is default — requires audit
- Node.js `vm` sandbox is not a true security boundary (prototype escape possible) — follow-up item
- Removing `manage_websets` raises the skill floor for agents that can only pass structured JSON (not generate JS code)
- `Server.oninitialized` callback exists in the MCP SDK — can be used for post-handshake logging

---

## Overview

Three targeted improvements to the schwartz13 Exa Websets MCP server, driven by an agent-native architecture audit that scored the server at 71%. These changes address the three weakest areas: context injection (20%), capability discovery (57%), and prompt-native features (55%). Estimated post-implementation score: ~82-85%.

## Problem Statement / Motivation

Agents connecting to the server face three friction points:
1. **Context blindness** — no account state on session start; agents must make multiple discovery calls to orient
2. **Unhelpful errors** — validation failures say what's wrong but not what to do ("Expected object, received string" vs "Use `{type: 'company'}`")
3. **Context tax** — `manage_websets` dumps 60 operations into the tool description (~1,800 chars) when `search` + `execute` already covers everything with progressive disclosure
4. **Format footguns** — agents consistently get entity/criteria formats wrong in sandbox code, triggering retry loops that could be auto-fixed

## Proposed Solution

Three phases, consolidated from the original five after simplicity review:

| Phase | Item | Effort | Dependency |
|-------|------|--------|------------|
| 1 | Safe compat default + prescriptive error hints | Low | None |
| 2 | Status tool | Medium | None (parallel with 1) |
| 3 | Deprecate manage_websets (rename + cleanup) | Low | After Phases 1-2 |

**Cut from original plan:** Phase 4 (MCP resource `account://status`) was removed. It duplicated the status tool, required a shared `accountStatus.ts` extraction that only existed to serve the resource, and MCP resource support varies across clients (no client auto-reads resources on connect). The status tool alone provides universal coverage.

## Technical Considerations

### Phase 1: Safe compat default + prescriptive error hints

#### 1a: Safe compat mode as default

**What changes:**
- `src/server.ts` lines 128 and 132: change `?? 'strict'` to `?? 'safe'` for both `registerManageWebsetsTool` and `registerExecuteTool`
- The `DEFAULT_COMPAT_MODE` environment variable already works (read at line 12 of `server.ts`) — this just changes the fallback
- Update `@default` JSDoc on `ServerConfig.defaultCompatMode` to document new default

**Why safe-first is correct:**
- The coercion system (`src/tools/coercion.ts`) already attaches `_coercions` metadata to responses, so agents see what was auto-fixed — no silent behavior
- Per-call override via `compat: { mode: 'strict' }` is preserved for callers who want strict validation
- The `preview` flag still works for dry-run coercion inspection
- Only well-defined coercions fire (entity strings to objects, criteria/options string arrays to object arrays, numeric/boolean string parsing) — ambiguous inputs still fail

**Why this reverses the documented strict-by-default principle:**
The solution doc `docs/solutions/2026-02-10-searchbox-default-compat-mode.md` says "preserve strict baseline." This reversal is justified because (a) agents are the primary callers and safe coercion eliminates 80%+ of format-related retry loops, (b) the `_coercions` metadata makes every fix transparent, and (c) the env var override preserves strict for callers who want it. After implementation, update the solution doc's "Prevention" section to reflect the new default and rationale.

**Edge cases:**
- `entity: "startup"` is NOT in `KNOWN_ENTITY_TYPES` (company, person, article, research_paper, custom) and will still fail validation. This is correct behavior — Phase 1b hints cover it.
- `entity: "custom"` will be coerced to `{type: "custom"}` but the API requires a `description` field. Either skip coercion for `"custom"` strings, or let the API return the error with a Phase 1b hint: `'For custom entity type, use {type: "custom", description: "Your entity description"}'`.

### Research Insights

**Pre-implementation audit required:** The `text` field appears in `BOOLEAN_FIELDS` (line 48 of coercion.ts). If any operation accepts a `text` parameter as a string (not a boolean), safe mode would coerce `"true"` or `"false"` string values into booleans, causing silent data corruption. Cross-reference `BOOLEAN_FIELDS` and `NUMERIC_FIELDS` against all 60 operation schemas before shipping. (Security review, HIGH severity)

**Coercion metadata propagation gap:** The `callOperation` wrapper in `sandbox.ts` (line 36-47) parses JSON results and strips metadata. After Phase 3 removes `manage_websets`, `execute` becomes the primary tool — but sandbox callers never see `_coercions`. Fix: have `callOperation` return `{ data, _coercions }` or at minimum log coercions via `capturedConsole.warn`. (Code Mode skill review)

#### 1b: Prescriptive error hints

**Inline hints — no new file needed.** The original plan proposed `src/tools/errorHints.ts` for 3 hint strings. This is over-engineered. Instead, add a simple `FIELD_HINTS` map at the top of `manageWebsets.ts` (or `operations.ts` after Phase 3):

```typescript
const FIELD_HINTS: Record<string, string> = {
  entity: 'entity must be an object like {type: "company"}, not a bare string. Known types: company, person, article, research_paper, custom. For custom: {type: "custom", description: "..."}.',
  criteria: 'criteria must be [{description: "..."}], not an array of strings.',
  options: 'options must be [{label: "..."}] with 1-20 items, not an array of strings.',
};
```

**Integration into `formatValidationError`:** After generating the Zod issue list, check each issue's `path[0]` against `FIELD_HINTS` and append matching hints.

**Two error paths need hints:**

1. **Zod validation path** (`formatValidationError` in manageWebsets.ts, line 288): Use the `FIELD_HINTS` map above.

2. **Handler error path** (`errorResult` in `src/handlers/types.ts`): Add hardcoded hint strings within each handler's catch block (NOT imported from a shared module — preserves one-way `tools/ -> handlers/` dependency direction). Audit existing hints in `exa.ts`, `searches.ts`, `enrichments.ts` to avoid double-hinting.

**API-level error hints — the biggest gap for agent self-correction:**

Add a catch-level hint resolver in `errorResult` itself that inspects HTTP status codes:
- 401/403: `"Check that EXA_API_KEY is set and valid."`
- 404 on webset/item ID: `"Not found. It may have been deleted. Use <entity>.list to find valid IDs."`
- 429: `"Rate limited. Wait before retrying or reduce request frequency."`
- 422: Include the raw API error message plus field-specific hints

**Execute tool error path:** After Phase 3, `execute` is the primary tool. Enrich `executeTool.ts` line 71-75 — when the error message matches known patterns (e.g., "Expected object, received string"), append the relevant hint. This is the highest-value hint location post-deprecation.

**Interaction with Phase 1a:** In safe mode, most format errors are auto-coerced and never reach validation. Hints primarily fire for: unknown entity types, non-coercible type mismatches, API-level errors (rate limits, auth, not-found), and missing required fields.

**Files:**
- `src/server.ts` — change default fallback (2 lines) + update JSDoc
- `src/tools/manageWebsets.ts` — add `FIELD_HINTS` map (5 lines), integrate into `formatValidationError`
- `src/tools/executeTool.ts` — add pattern-matched hints to error catch
- `src/handlers/types.ts` — add HTTP status code hint resolver to `errorResult`
- Selected handlers (`websets.ts`, `monitors.ts`, `items.ts`, `tasks.ts`, `exa.ts`) — add contextual hints to `errorResult` calls

---

### Phase 2: Status tool

**New tool `status`** — single call returning account overview with agent orientation data.

**Registration:** `src/tools/statusTool.ts` — new file following the three-part internal structure: module-scope `inputSchema`, module-scope `DESCRIPTION`, exported `registerStatusTool` function. Mark with `readOnlyHint: true` annotation.

**Input schema:** Empty object (no parameters needed).

**Response shape:**

```typescript
export interface AccountStatus {
  websets: {
    count: number;
    hasMore: boolean; // Exa pagination has no 'total' field — flag if more exist
    by_status: Partial<Record<WebsetStatus, number>>; // 'idle'|'searching'|'enriching'|'monitoring'|'canceled'
    recent: Array<{ id: string; status: string; query: string }>; // last 5 for quick reference
  };
  tasks: {
    running: number;
    active: Array<{ taskId: string; type: string }>; // running task IDs + types
    recent_errors: Array<Pick<TaskError, 'step' | 'message'> & { taskId: string }>;
  };
  monitors: {
    active: number;
  };
  capabilities: {
    tools: string[];
    operationCount: number;
    compatMode: 'safe' | 'strict';
    hint: string; // e.g., "Use search tool to discover specific operations"
  };
  timestamp: string; // ISO 8601
}
```

### Research Insights

**Factual correction:** The original plan listed `by_status` keys as `idle, processing, paused, completed`. The actual `Webset['status']` union in the codebase is `'idle' | 'searching' | 'enriching' | 'monitoring' | 'canceled'`. Use `Partial<Record<Webset['status'], number>>` to stay coupled to the source of truth. (TypeScript review, HIGH severity)

**No `total` in Exa pagination:** The Exa API returns `{data, hasMore, nextCursor}` but no total count. Return `{count: N, hasMore: boolean}` instead of a single `total` number. (Agent-native skill review)

**Why include `recent` and `active`:** Without identifiers, the status tool tells agents "what exists" but not "what to reference" — forcing a follow-up `websets.list` call every time, defeating the purpose. Last 5 websets as `{id, status, query}` plus active task IDs eliminate the most common follow-up calls. (Agent-native parity review)

**Why include `capabilities`:** Agents confirming their toolset normally call `listTools`. Including available tools, operation count, and current compat mode provides immediate orientation without a separate round-trip. (Code Mode skill, best practices research)

**Implementation strategy — resilient, cached aggregation:**

```typescript
const CACHE_TTL_MS = 10_000; // 10 seconds — status data is stale-tolerant
const STATUS_TIMEOUT_MS = 3_000;

let cached: { data: AccountStatus; expiresAt: number } | null = null;

export async function getAccountStatus(exa: Exa): Promise<AccountStatus> {
  if (cached && Date.now() < cached.expiresAt) return cached.data;

  const results = await Promise.race([
    Promise.allSettled([
      exa.websets.list(),
      exa.websets.monitors.list(),
    ]),
    new Promise<never>((_, reject) =>
      setTimeout(() => reject(new Error('Status timed out')), STATUS_TIMEOUT_MS)
    ),
  ]);

  // taskStore.list() is instant (in-memory), always succeeds
  const tasks = taskStore.list();
  // Build response from settled results, using null for failed/timed-out calls
  // ...
}
```

**Key design decisions:**
- `Promise.allSettled` (not `Promise.all`) — returns partial data if one API call fails. Task store data (instant, local) is always available even if Exa API is down.
- `Promise.race` with 3-second timeout — prevents degraded Exa endpoints from blocking the MCP response
- 10-second TTL cache — global (single `exa` instance shared across sessions). Without caching, 50 concurrent sessions initializing = 100 API calls. With cache, those collapse to 2.
- Sanitize `recent_errors` — strip raw API error details, keep only step + generic message to prevent information disclosure (Security review, MEDIUM)

**E2E test considerations:** Phase 2 adds a 4th tool. Update `transport.test.ts` to `toHaveLength(4)` and expect `['execute', 'manage_websets', 'search', 'status']`. Phase 3 will change this to 3 tools. (Architecture review)

**Files:**
- `src/tools/statusTool.ts` — new file (schema, description, registerStatusTool)
- `src/server.ts` — import and register `registerStatusTool`
- `src/__tests__/e2e/transport.test.ts` — update to expect 4 tools

---

### Phase 3: Deprecate manage_websets

**Simplified approach: rename, don't extract.**

The original plan proposed creating a new `operations.ts` alongside `manageWebsets.ts`. The simpler path: **rename `manageWebsets.ts` to `operations.ts` and delete the registration code from it.** The file already contains everything that needs to survive (`OPERATIONS`, `OPERATION_SCHEMAS`, `dispatchOperation`, etc.). The registration function is ~30 lines at the bottom. (Simplicity review)

**Step 1: Create `src/workflows/index.ts`** barrel for side-effect imports:

```typescript
// src/workflows/index.ts
import './echo.js';
import './qdWinnow.js';
import './researchDeep.js';
// ... all 11 workflow imports
```

This decouples the operation registry from workflow initialization and makes the dependency explicit. (Architecture review)

**Step 2: Rename `manageWebsets.ts` to `operations.ts`.**

**Step 3: Delete from `operations.ts`:**
- `registerManageWebsetsTool` function
- `buildToolDescription` function
- `buildInputSchema` function
- `ManageWebsetsOptions` type
- `normalizeInput` function (only used by deleted tool handler)
- `isRecord` helper (only used by `normalizeInput`)
- The 11 individual workflow side-effect imports (moved to `workflows/index.ts`)

**Keep in `operations.ts`:**
- `OPERATIONS` registry and `OperationMeta` type
- `OPERATION_SCHEMAS` registry
- `OPERATION_NAMES` typed array
- `dispatchOperation()` function
- `withCoercionMetadata()` function (used by `dispatchOperation`)
- `formatValidationError()` function (uses inline `FIELD_HINTS` from Phase 1)
- All 11 handler imports
- `import '../workflows/index.js'` (single barrel import)

**Step 4: Update imports** in `catalog.ts`, `sandbox.ts`, `executeTool.ts` to `./operations.js`.

**Step 5: Remove `registerManageWebsetsTool`** call from `server.ts`.

**Step 6: Update E2E tests:**
- `transport.test.ts`: change to `toHaveLength(3)` and assert `expect(result.tools.map(t => t.name).sort()).toEqual(['execute', 'search', 'status'])` — name-based assertion, not just count
- Migrate the CRUD lifecycle test to use `execute` with `callOperation()`:
  ```typescript
  it('full lifecycle via execute', async () => {
    const result = await ctx.client.callTool({
      name: 'execute',
      arguments: {
        code: `
          const ws = await callOperation('websets.create', {
            searchQuery: 'E2E test', searchCount: 5,
            entity: { type: 'company' }
          });
          const got = await callOperation('websets.get', { id: ws.id });
          await callOperation('websets.cancel', { id: ws.id });
          await callOperation('websets.delete', { id: ws.id });
          return { created: ws.id, verified: got.id === ws.id };
        `
      }
    });
    expect(result.isError).toBeFalsy();
  });
  ```
- Remove the 4 `manage_websets`-specific tests
- `health.test.ts`: no changes needed

**Step 7: Clean up `as any` casts.** During the rename, remove gratuitous `(coercion as any).preview` and `(coercion as any).effectiveMode` casts — `CoercionResult` already types these fields correctly. (TypeScript review)

### Research Insights

**Critical ordering regression risk:** The solution doc `docs/solutions/2026-02-10-manage-websets-coercion-validation-regression.md` documents a prior regression caused by moving validation relative to coercion during a dispatcher refactor. The dispatch ordering `normalize -> coerce -> validate -> execute` is load-bearing. Add a regression test that exercises the full path through `dispatchOperation` with safe coercion enabled. (Learnings analysis, HIGH severity)

**Workflow side-effect import ordering:** The 11 side-effect imports register workflows into `workflowRegistry`. If `operations.ts` is imported without the workflow barrel, `tasks.create` silently fails (empty registry). The `import '../workflows/index.js'` at the top of `operations.ts` ensures workflows are always registered before dispatch. (Architecture review, agent-native parity review)

**Skill floor trade-off:** Removing `manage_websets` means agents must generate JavaScript for `execute` instead of passing flat JSON args. This is a deliberate trade-off: context tax reduction for sophisticated agents (Claude, GPT-4) at the cost of the low-skill-floor direct-invocation path. If user feedback shows the skill floor is too high, consider adding a lightweight `call` tool (`{operation, args}` — no code generation required) as a future option. (Agent-native parity review)

**Files:**
- `src/tools/manageWebsets.ts` — renamed to `src/tools/operations.ts`, registration code deleted
- `src/workflows/index.ts` — new barrel file for side-effect imports
- `src/tools/catalog.ts` — update import path
- `src/tools/sandbox.ts` — update import path
- `src/tools/executeTool.ts` — update import path
- `src/server.ts` — remove `registerManageWebsetsTool` import and call
- `src/__tests__/e2e/transport.test.ts` — update assertions and migrate tests
- `TOOL_SCHEMAS.md` — remove manage_websets section
- `CLAUDE.md` — update tool list to `search`, `execute`, `status`

---

## Security Considerations

Findings from the security review, ordered by severity:

| # | Finding | Severity | Phase | Action |
|---|---------|----------|-------|--------|
| 1 | Raw `exa` SDK client in sandbox exposes API key via prototype inspection | CRITICAL | 3 | Remove `exa` from sandbox context — `callOperation` covers all operations |
| 2 | `text` in `BOOLEAN_FIELDS` may collide with string parameters | HIGH | 1 | Audit all 60 operation schemas for field-name collisions before shipping |
| 3 | Node.js `vm` is not a security boundary (prototype chain escape) | HIGH | Follow-up | Replace with `isolated-vm` or add prototype escape test |
| 4 | Status tool has no rate limiting — 3x API amplification per call | MEDIUM | 2 | 10-second TTL cache (in plan) |
| 5 | `recent_errors` may leak implementation details | MEDIUM | 2 | Sanitize error messages in status response |
| 6 | Client-controlled session IDs | MEDIUM | Follow-up | Always generate server-side IDs |

**Action for Phase 3:** When extracting sandbox globals during the rename, remove `exa` from the `vm.createContext` call in `sandbox.ts`. The `callOperation` global already routes through `dispatchOperation` with coercion, validation, and error handling. Removing `exa` narrows the attack surface with no loss of functionality and aligns with the Code Mode skill's security model.

---

## System-Wide Impact

- **Interaction graph**: Phase 1 modifies the dispatch path (coerce default + hint enrichment). Phase 2 adds a new read-only tool. Phase 3 removes a tool registration, renames the infrastructure module, and removes `exa` from the sandbox.
- **Error propagation**: Phase 1 enriches error messages and adds API-level hints but does not change the error flow. All errors still return `{ isError: true }` ToolResult shape.
- **State lifecycle risks**: None — all changes are stateless or read-only. The task store is unmodified. The status tool cache is in-memory with TTL expiry.
- **API surface parity**: After Phase 3, tool count is 3 (search, execute, status). The `execute` tool's `callOperation()` sandbox global still routes through `dispatchOperation`, so all 60 operations remain accessible.
- **Dispatch ordering invariant**: normalize -> coerce -> validate -> execute. This ordering is preserved across all phases and verified by regression test.

## Acceptance Criteria

### Phase 1: Safe defaults with prescriptive errors
- [ ] Default compat mode is `'safe'` when no env var or config is set
- [ ] `DEFAULT_COMPAT_MODE=strict` env var still overrides to strict
- [ ] Per-call `compat: { mode: 'strict' }` still works
- [ ] Coercion metadata (`_coercions`) appears in responses when coercions fire
- [ ] `BOOLEAN_FIELDS` and `NUMERIC_FIELDS` audited against all 60 operation schemas — no string-param collisions
- [ ] Zod validation errors for `entity`, `criteria`, `options` fields include format examples
- [ ] At least 5 handlers pass contextual hints to `errorResult`
- [ ] API-level errors (401, 404, 429, 422) include prescriptive hints
- [ ] Execute tool error path enriched with pattern-matched hints
- [ ] Existing E2E tests pass
- [ ] Solution doc `docs/solutions/2026-02-10-searchbox-default-compat-mode.md` updated with new default rationale

### Phase 2: Status tool
- [ ] `status` tool registered with `readOnlyHint: true` annotation and appears in `listTools`
- [ ] Returns `AccountStatus` interface with webset counts (using correct `Webset['status']` union), recent websets, active tasks, capabilities
- [ ] `hasMore` flag indicates whether first-page aggregation is complete
- [ ] 10-second TTL cache prevents API amplification
- [ ] 3-second timeout prevents degraded API from blocking response
- [ ] `Promise.allSettled` returns partial data if one API call fails
- [ ] `recent_errors` sanitized (no raw API error details)
- [ ] Works with empty accounts (no websets, no tasks)
- [ ] E2E test for status tool (expect 4 tools during this phase)

### Phase 3: Deprecate manage_websets
- [ ] `manageWebsets.ts` renamed to `operations.ts`
- [ ] `registerManageWebsetsTool`, `buildToolDescription`, `buildInputSchema`, `normalizeInput`, `isRecord` deleted
- [ ] `src/workflows/index.ts` barrel created with all 11 side-effect imports
- [ ] `operations.ts` imports from `../workflows/index.js` (single barrel)
- [ ] `manage_websets` no longer appears in `listTools`
- [ ] `search` and `execute` tools unaffected (still work via `dispatchOperation`)
- [ ] Raw `exa` removed from sandbox context in `sandbox.ts`
- [ ] Gratuitous `as any` casts removed from `dispatchOperation`
- [ ] Dispatch ordering regression test added (normalize -> coerce -> validate -> execute through full tool path)
- [ ] E2E tests updated: assert 3 tools `['execute', 'search', 'status']`, CRUD lifecycle migrated to `execute`
- [ ] `CLAUDE.md` and `TOOL_SCHEMAS.md` updated

## Dependencies & Risks

| Risk | Mitigation |
|------|------------|
| Changing default compat mode could mask bugs in agent code | Coercion metadata in responses makes fixes visible; per-call strict override preserved; reversal documented |
| `BOOLEAN_FIELDS`/`NUMERIC_FIELDS` name collisions | Pre-implementation audit against all 60 schemas required |
| Status tool latency on large accounts | First-page-only + 10s TTL cache + 3s timeout + `Promise.allSettled` graceful degradation |
| Removing manage_websets breaks existing MCP client configs | Code Mode tools already registered; manage_websets labeled legacy; consider stub tool returning migration message |
| Removing `exa` from sandbox breaks sandbox code using `exa.*` directly | `callOperation` covers all operations; update sandbox description to remove `exa` references |
| Phase 3 rename could re-introduce dispatch ordering regression | Regression test exercising full normalize -> coerce -> validate -> execute path (documented in Learning 3) |
| Workflow side-effect imports lost during rename | `workflows/index.ts` barrel ensures all workflows are registered; explicit acceptance criterion |

## Follow-Up Items (Out of Scope)

These were identified during deepening but are not part of this refactor:

1. **Replace `vm` with `isolated-vm`** — Node.js `vm` is not a security boundary. Prototype chain escape is possible. (Security, HIGH)
2. **Sandbox memory limits** — No `max_memory` enforcement. Node `vm` does not support it natively. Consider `isolated-vm` or `process.memoryUsage()` monitoring. (Code Mode skill)
3. **Fix session ID handling** — Server accepts client-provided session IDs for new sessions (line 99 of `server.ts`). Should always generate server-side. (Security, MEDIUM)
4. **Lightweight `call` tool** — If removing `manage_websets` raises the skill floor too high, add a `call` tool (`{operation, args}` — no JS code generation required). (Agent-native parity)
5. **`withCoercionMetadata` JSON re-parse** — Parses response JSON, adds `_coercions`, re-serializes. Could be refactored to pass structured data alongside text. (Performance, LOW)

## Sources & References

### Internal References
- Architecture: `src/server.ts` (session setup, tool registration)
- Dispatch: `src/tools/manageWebsets.ts` (OPERATIONS registry, dispatchOperation)
- Catalog: `src/tools/catalog.ts` (search index, detail levels)
- Sandbox: `src/tools/sandbox.ts` (vm execution, globals)
- Coercion: `src/tools/coercion.ts` (safe mode, known entity types)
- Error types: `src/handlers/types.ts` (errorResult, requireParams)
- ADR-001: `docs/adr/001-unified-dispatcher-refactoring.md` (why single dispatcher)
- ADR-002: `docs/adr/002-response-projection-tiers.md` (response optimization)
- Coercion solution: `docs/solutions/2026-02-10-searchbox-safe-coercion.md`
- Default compat solution: `docs/solutions/2026-02-10-searchbox-default-compat-mode.md`
- Ordering regression: `docs/solutions/2026-02-10-manage-websets-coercion-validation-regression.md`
- Code Mode skill: `/workspaces/openchatwidget/.agents/skills/code-mode-servers/SKILL.md`
- MCP SDK v1.26.0: `@modelcontextprotocol/sdk` — `registerResource`, `RegisteredTool.disable()/remove()`, `Server.oninitialized`, `ToolAnnotations`

### External References
- MCP tool annotations: `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint` — no `deprecated` field exists
- MCP resource client support: Claude Desktop (yes), Cursor (partial), Windsurf (no) — tools are universally supported

### Audit Source
- Agent-native architecture review scoring 71% overall, with action parity (100%), context injection (20%), discovery (57%), prompt-native features (55%)
