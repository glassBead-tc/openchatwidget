# schwartz13

Docker-first MCP server for [Exa's Websets API](https://docs.exa.ai/reference/websets).
The current runtime model is an HTTP MCP server behind Docker. It is not a published npm
package today, and any non-Docker path should be treated as future work until we design it
explicitly.

## Current Shape

- MCP transport: HTTP at `/mcp`
- Primary runtime: Docker Compose
- Primary server entrypoints:
  - `src/index.ts`
  - `src/server.ts`
- Unified tool surface: `manage_websets`

## Quick Start

### Prerequisites

- Docker / Docker Compose
- `EXA_API_KEY`

### Run

```bash
EXA_API_KEY=your-key docker compose up --build
```

The server listens on port `7860` by default.

### Connect an MCP Client

```json
{
  "mcpServers": {
    "schwartz13": {
      "type": "http",
      "url": "http://localhost:7860/mcp"
    }
  }
}
```

## Local Development

Docker is the primary runtime, but local Node-based development is still useful while
iterating on the server:

```bash
npm install
npm run build
npm start
```

## Unified Tool

The server exposes a single MCP tool, `manage_websets`, which dispatches across the Websets,
search, enrichment, monitoring, task, research, and Exa retrieval operations.

Example:

```json
{
  "operation": "websets.create",
  "args": {
    "searchQuery": "AI startups in San Francisco",
    "searchCount": 20,
    "entity": { "type": "company" }
  }
}
```

Long-running workflows are created with `tasks.create` and polled with `tasks.get` /
`tasks.result`.

## Compatibility Mode

`MANAGE_WEBSETS_DEFAULT_COMPAT_MODE` controls the default argument coercion mode:

- `strict` (default)
- `safe`

Per-call `args.compat.mode` overrides the server default.

## Validation Footguns

- `criteria` must be objects: `[{"description":"..."}]`
- `entity` must be an object: `{"type":"company"}`
- `options` must be objects: `[{"label":"..."}]`
- `cron` must use 5 fields

## Useful Commands

```bash
npm test
npm run test:integration
npm run test:e2e
npm run test:workflows
docker compose up --build
docker compose down
```

## Resources

- [Exa Websets Documentation](https://docs.exa.ai/reference/websets)
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
