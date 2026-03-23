# ADR-001: Unified Dispatcher Refactoring

**Status**: Accepted
**Date**: 2026-02-05
**Deciders**: b.c.nims
**HDD Epic**: searchbox-zs0

## Context

The Exa Websets MCP Server currently registers 14 individual tools (`create_webset`, `list_websets`, `get_webset`, etc.). Each tool has its own file under `src/tools/`, its own Zod schema, and its own registration call. This creates several problems:

1. **Context bloat**: MCP clients (Claude, Cursor) receive 14 tool definitions in their system prompt, consuming tokens on every turn even when websets aren't being used.
2. **Missing operations**: The exa-js SDK supports 38 websets operations across 8 domains. Only 14 are exposed, leaving webhooks, imports, events, and many CRUD operations unavailable.
3. **Redundant code**: `src/utils/schemas.ts` duplicates Zod schemas already inline in tool files. `src/tools/config.ts` defines API endpoints unused by the exa-js SDK. `src/handlers/websets.ts` re-parses args through schemas.ts but isn't wired into the server.
4. **Scaling pain**: Adding each new operation requires a new file, a new import, a new registration call, and updates to `enabledTools`.

## Decision

Replace all 14 individual MCP tools with a **single `manage_websets` dispatcher tool** that accepts an `operation` enum and `args` object. Implement all 38 exa-js SDK websets operations across 8 domain handler files.

### Architecture

```
src/
├── lib/exa.ts                     # Keep: singleton Exa client
├── handlers/
│   ├── types.ts                   # NEW: ToolResult, OperationHandler, helpers
│   ├── websets.ts                 # REPLACE: 7 ops (create, get, list, update, delete, cancel, preview)
│   ├── searches.ts                # NEW: 3 ops
│   ├── items.ts                   # NEW: 3 ops
│   ├── enrichments.ts             # NEW: 5 ops
│   ├── monitors.ts                # NEW: 7 ops (including runs.list, runs.get)
│   ├── webhooks.ts                # NEW: 6 ops (including list_attempts)
│   ├── imports.ts                 # NEW: 5 ops
│   └── events.ts                  # NEW: 2 ops
├── tools/
│   └── manageWebsets.ts           # NEW: single dispatcher tool
├── utils/
│   └── logger.ts                  # Keep
└── index.ts                       # MODIFY: 14 registrations → 1
```

### Input Schema (Thoughtbox pattern)

```typescript
const inputSchema = {
  operation: z.enum([...ALL_38_OPERATION_NAMES]),
  args: z.record(z.string(), z.unknown()).optional()
};
```

### Dispatch Mechanism

Map-based dispatch (not switch) since all operations are equally available:

```typescript
const registry = new Map<string, OperationHandler>();
// populated from each domain handler module
```

### Handler Signature

```typescript
type OperationHandler = (args: Record<string, unknown>, exa: Exa) => Promise<ToolResult>;
type ToolResult = { content: Array<{ type: 'text'; text: string }>; isError?: boolean };
```

## Operations (38 total)

| Domain | Operations | Count |
|--------|-----------|-------|
| websets | create, get, list, update, delete, cancel, preview | 7 |
| searches | create, get, cancel | 3 |
| items | list, get, delete | 3 |
| enrichments | create, get, cancel, update, delete | 5 |
| monitors | create, get, list, update, delete, runs.list, runs.get | 7 |
| webhooks | create, get, list, update, delete, list_attempts | 6 |
| imports | create, get, list, update, delete | 5 |
| events | list, get | 2 |

## Preserved Application-Level Validations

These validations exist in current tools and must be preserved in handlers:

1. **enrichments.create**: When `format === 'options'`, `options` array is required and max 150 items
2. **monitors.create**: Cron expression must have exactly 5 fields
3. **searches.create**: Error messages include "Common issues" hints for parameter format

## Hypotheses

### H1: Single tool compiles without type errors
- **Prediction**: `npm run build` succeeds with zero type errors after full implementation
- **Validation**: Automated — run build
- **Falsification**: Any TypeScript compilation error

### H2: Application-level validations produce equivalent error messages
- **Prediction**: enrichment options validation, cron validation, and search error hints produce the same user-facing messages
- **Validation**: Unit tests comparing old vs new error output strings
- **Falsification**: Any validation that silently passes or produces a different error message

### H3: `z.record(z.string(), z.unknown())` args pass through to exa-js SDK correctly
- **Prediction**: The flexible args record doesn't require type conversion before calling SDK methods. Casting `args.fieldName as Type` works correctly.
- **Validation**: Unit tests with mock exa client verifying correct args forwarded
- **Falsification**: SDK rejects args that the old tools accepted, or type assertions fail at runtime

### H4: Deleting 16 old files leaves no broken imports
- **Prediction**: After removing 14 tool files + schemas.ts + config.ts, `npm run build` succeeds
- **Validation**: Automated — run build after deletion
- **Falsification**: Any import resolution error

### H5: 38-operation tool description is usable by AI clients
- **Prediction**: The tool description listing all 38 operations with parameter hints fits within practical limits and AI callers can select the correct operation
- **Validation**: Manual — tool registers successfully, description is readable
- **Falsification**: MCP SDK rejects registration, or description is too large/confusing

## Files to Delete (16)

```
src/tools/createWebset.ts
src/tools/listWebsets.ts
src/tools/getWebset.ts
src/tools/updateWebset.ts
src/tools/deleteWebset.ts
src/tools/listItems.ts
src/tools/getItem.ts
src/tools/createSearch.ts
src/tools/getSearch.ts
src/tools/cancelSearch.ts
src/tools/createEnrichment.ts
src/tools/getEnrichment.ts
src/tools/cancelEnrichment.ts
src/tools/createMonitor.ts
src/tools/config.ts
src/utils/schemas.ts
```

Also replace (not delete): `src/handlers/websets.ts`

## Consequences

### Positive
- Token usage drops from ~14 tool definitions to 1
- All 38 SDK operations exposed (was 14)
- Single point of registration, error handling, logging
- Adding operations = adding a handler function + registry entry

### Negative
- Breaking change: old tool names no longer work (major version bump to 2.0.0)
- AI callers must learn `operation` + `args` pattern instead of named tools
- Debugging requires knowing which operation was called (mitigated by logging)

### Risks
- Large tool description may confuse some AI callers → mitigated by clear operation grouping
- `z.record` flexibility means less Zod-level validation of individual args → mitigated by SDK-level validation + preserved application checks
