# Implementation Kickoff: Long-Horizon Tasks & Research Patterns

## Context

Read the specification at `research-workflows/long-horizon-spec.md`. It describes a 3-layer extension to the Searchbox MCP server (Exa Websets):

- **Layer 1** (existing): 47 primitive operations across 8 domains
- **Layer 2** (new): Exa Research API domain (4 operations)
- **Layer 3** (new): Server-internal task orchestrator (5 management operations + 6 composite task types)

The server exposes a single MCP tool `manage_websets` via a unified dispatcher in `src/tools/manageWebsets.ts`. All new operations are added to the same OPERATIONS registry. Handler signature: `(args: Record<string, unknown>, exa: Exa) => Promise<ToolResult>`.

## What to implement

Execute the 5-phase implementation roadmap from the spec. Each phase should be a separate commit with tests.

### Phase 1: Foundation

Create the task infrastructure:

1. **`src/lib/taskStore.ts`** — In-memory TaskStore (Map-based). Exports a module-level singleton so task handlers can import it without signature changes. Types: `TaskStatus`, `TaskProgress`, `TaskState`, `TaskStore` interface. Features: UUID generation with `task_` prefix, TTL-based expiration (default 1h), periodic cleanup (5min interval), max 20 concurrent tasks.

2. **`src/lib/semaphore.ts`** — Simple counting semaphore for rate-limiting parallel Exa API calls within workflows. Default 3 permits.

3. **`src/workflows/types.ts`** — `WorkflowFunction` type signature: `(taskId, args, exa, store) => Promise<unknown>`. Plus a task type registry mapping type names to workflow functions.

4. **`src/handlers/tasks.ts`** — Five handlers: `create` (spawns background workflow via untracked Promise), `get` (status + progress), `result` (completed result or error), `list` (enumerate by status), `cancel`. The `create` handler looks up the task type in the workflow registry, creates a TaskState, fires off the workflow function, and returns `{taskId, status}` immediately. Include a dummy `echo` task type for testing.

5. **`src/tools/manageWebsets.ts`** — Add 5 task operations to OPERATIONS registry.

6. **Unit tests** in `src/handlers/__tests__/tasks.test.ts` and `src/lib/__tests__/taskStore.test.ts`. Test: create/get/list/cancel lifecycle, TTL expiration, concurrent task limit, echo task type end-to-end.

**Done when**: `tasks.create({type: 'echo', message: 'hello'})` returns a taskId, `tasks.get` shows progress, `tasks.result` returns the echo'd message. All tests pass.

### Phase 2: Research API Domain

1. **`src/handlers/research.ts`** — Four handlers wrapping `exa.research.*`:
   - `create`: `exa.research.create({instructions, outputSchema?, model?})` → returns `{researchId, status}`
   - `get`: `exa.research.get(researchId)` → returns status + result if complete
   - `list`: `exa.research.list()` → returns paginated research tasks
   - `pollUntilFinished`: `exa.research.pollUntilFinished(researchId)` → blocks until complete, returns result

2. Register 4 operations in `manageWebsets.ts`.

3. **Unit tests** mocking Exa client (same pattern as existing handler tests).

4. **Integration tests** (gated on `EXA_API_KEY`) — create a real research task, poll it, verify structured output.

**Done when**: `research.create({instructions: '...'})` works, `research.pollUntilFinished` returns a result. Tests pass.

### Phase 3: QD Winnowing Workflow

This is the foundational composite pattern. Implement `src/workflows/qdWinnow.ts`:

1. Create webset with criteria + enrichments (or append to `seedWebsetId`)
2. Poll until idle, reporting progress with found/analyzed ratio (stringency signal)
3. Collect items with evaluations and enrichment results
4. Classify items into niches (criteria satisfaction vectors like `"1,1,0"`)
5. Score fitness per item from enrichment results
6. Select elites (best per niche)
7. Compute quality metrics (coverage, avgFitness, diversity, stringency)
8. Generate descriptor feedback (per-criterion successRate analysis)
9. If `critique: true`, call Research API to evaluate results
10. Return structured result with rounds, elites, metrics, descriptor feedback

Key details from the spec:
- Niche key = criteria satisfaction vector as string (e.g., `"1,1,0"`)
- Fitness = mean of normalized enrichment scores
- Enrichment scoring: number→direct, boolean/options→0|1, text/url→presence
- `seedWebsetId` uses `searches.create` with `behavior:'append'`
- Progress updates at each step via `store.updateProgress`
- Partial results set at checkpoints via `store.setPartialResult`
- Check for cancellation via `store.get(taskId).status` between steps

**Done when**: Full end-to-end integration test — create a qd.winnow task with 2-3 criteria and 1-2 enrichments, poll status, get result with niches/elites/metrics.

### Phase 4: Derived Workflows

Implement the remaining 5 task types, each in its own file under `src/workflows/`:

1. **`lifecycle.ts`** — Simplified qd.winnow: 1 round, `all-criteria` selection, with explicit enrichment-add step
2. **`convergent.ts`** — N parallel webset creates (use semaphore), collect all, deduplicate by URL, compute intersection
3. **`adversarial.ts`** — Thesis/antithesis websets, optional Research API synthesis
4. **`researchDeep.ts`** — Thin wrapper: create Research API task, poll, return result
5. **`verifiedCollection.ts`** — Webset collection → per-entity Research API calls (parallel with semaphore)

All support optional `critique: boolean` flag.

### Phase 5: Polish

1. Insert MAP-Elites workflow entries into `research-workflows/workflows.db`
2. Update CLAUDE.md operations table
3. Error path tests for all workflows
4. Docker rebuild verification
5. Version bump to 3.0.0

## Critical constraints

- **Handler signature**: `(args: Record<string, unknown>, exa: Exa) => Promise<ToolResult>` — don't change this. Task handlers import the singleton TaskStore.
- **TypeScript strict mode**: Use `if (args.x) params.x = args.x` pattern, NOT spread of unknown values.
- **Testing**: Unit tests mock the Exa client. Integration tests are gated on `EXA_API_KEY`. Use `describe.skipIf(!HAS_API_KEY)`.
- **Vitest config**: `fileParallelism: false`, `hookTimeout: 30_000` for integration tests.
- **Build**: `npm run build` must pass after every phase. `npx vitest run` must pass.
- **Existing tests**: All 127 existing tests must continue to pass. Zero regressions.
- **Beads**: `searchbox-ewn` is the tracking bead. Update status as you go.

## Important gotchas from the spec

- `exa.research.create()` / `pollUntilFinished()` — verify exact TypeScript types before implementing. The SDK types may differ from docs.
- `searches.create` requires `behavior` field ("append"|"override") — not optional.
- Enrichment `options` format requires `[{label: "..."}]` array of objects.
- Task handlers fire-and-forget background workflows — use `void workflow().catch(err => store.setError(...))`, NOT `await workflow()`.
- The TaskStore singleton means it's shared across all sessions. Task IDs should be globally unique.
- `websets.waitUntilIdle` has 300s default timeout — may not be enough for large websets in QD winnowing. Allow per-task timeout override.
