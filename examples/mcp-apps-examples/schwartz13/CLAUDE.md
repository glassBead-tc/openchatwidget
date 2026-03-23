# CLAUDE.md

This repository is currently a Docker-first MCP server for Exa Websets.

## Working Assumptions

- Treat Docker and HTTP transport as the primary runtime.
- Do not treat this as a published npm package.
- If we add a non-Docker path later, that should be designed deliberately rather than inferred
  from stale docs.

## Useful Commands

```bash
docker compose up --build
npm run build
npm test
npm run test:e2e
```

## Architecture Snapshot

- `src/index.ts` boots the Express app and listens on port `7860`.
- `src/server.ts` exposes MCP over `StreamableHTTPServerTransport` at `/mcp`.
- `src/tools/manageWebsets.ts` registers the unified `manage_websets` tool.
- `src/handlers/` contains the domain handlers.
- `src/workflows/` contains background workflows invoked through `tasks.create`.

## Agent Guidance

- Keep docs aligned with Docker-first operation.
- Prefer removing stale local assistant scaffolding over preserving broken historical flows.
- For the load-bearing skill during this refactor, use
  `/workspaces/openchatwidget/.agents/skills/code-mode-servers/SKILL.md`.
