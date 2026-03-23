# Unified Tool Dispatcher Refactoring Plan

## Objective

Consolidate all individual MCP tools into a single "Unified Dispatcher" tool (`manage_websets`) to provide better context control for the MCP client.

## Reference Pattern

Based on the implementation in new-websets-server, we will adopt the **Toolhost Pattern**:

- **One Tool**: `manage_websets` (or `exa`)
- **Inputs**: `operation` (enum) and `args` (object)
- **Handlers**: Separate modules for each domain (websets, searches, items, etc.)

## Implementation Steps

### 1. Define Schemas (`src/utils/schemas.ts`)

Create a central schema definition file using Zod.

- **Base Schemas**: `ResponseFormat`, `Pagination`, `Metadata`
- **Operation Schemas**: `CreateWebset`, `ListWebsets`, `CreateSearch`, `GetItem`, etc.
- **Goal**: Replicate the rigorous validation from the reference project.

### 2. Create Handlers (`src/handlers/`)

Refactor logic from individual tool files into domain-specific handlers.

- `src/handlers/websets.ts` (create, get, list, update, delete, cancel)
- `src/handlers/searches.ts` (create, get, cancel)
- `src/handlers/items.ts` (list, get, delete)
- `src/handlers/enrichments.ts` (create, get, cancel)
- `src/handlers/monitors.ts` (create)
- `src/handlers/registry.ts` (Map operations to handlers)

### 3. Implement Dispatcher Tool (`src/tools/manageWebsets.ts`)

Create the single MCP tool definition.

- **Name**: `manage_websets`
- **Schema**: `ToolhostInvokeSchema` (operation enum + args)
- **Logic**: Import registry, dispatch request to appropriate handler.

### 4. Update Server Entry (`src/index.ts`)

- Remove all `register*Tool` calls.
- Register only `registerManageWebsetsTool`.

### 5. Cleanup

- Delete old files in `src/tools/` (e.g., `createWebset.ts`, `getWebset.ts`...).
