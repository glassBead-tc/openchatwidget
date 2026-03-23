# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Open Chat Widget is an open-source React chat widget SDK (`@openchatwidget/sdk`) that integrates with the Vercel AI SDK to add streaming AI chat to any web app. It supports tool execution with human-in-the-loop approvals, file attachments, reasoning display, and MCP (Model Context Protocol).

## Commands

All commands are run from `sdk/`:

```bash
# Development (Vite client on 127.0.0.1:5173 + Hono server on 8787)
npm run dev

# Build the SDK (Vite → postbuild CSS fix → TypeScript declarations)
npm run build

# Lint (zero warnings allowed)
npm run lint

# Format check / format
npm run format:check
npm run format
```

There is no test suite — CI only runs lint and format checks (`.github/workflows/sdk-quality.yml`).

## Architecture

### SDK Package (`sdk/`)

The publishable package is built from two source trees:

- **`sdk/widget/src/`** — the React widget and all its components (what gets bundled)
- **`sdk/build/index.ts`** — build entry point (referenced in `vite.config.ts`)
- **`sdk/sandbox/`** — local dev environment (not shipped); a Hono server + Vite app for testing the widget

**Build pipeline**: Vite bundles to `dist/index.js` (ESM only, ES2022 target). The postbuild script (`sdk/scripts/postbuild.mjs`) renames `style.css` → `index.css` and prepends a CSS import into the JS bundle. Then `tsc` emits type declarations only. Tailwind CSS is bundled into the output — consumers don't need to configure it.

**External dependencies** (not bundled): `react`, `react-dom`, `ai`, `@ai-sdk/*`, `react-markdown`, `remark-gfm`.

### Widget Architecture (`sdk/widget/src/`)

- **`OpenChatWidget.tsx`** — root component. Owns all state (open/closed, input, attachments, viewport) and wires `useChat` from `@ai-sdk/react` to the backend URL. Renders `WidgetPanel` + `ChatToggleButton`.
- **`index.ts`** — public API surface. Exports the component, props type, server utilities, and key Vercel AI SDK re-exports (`convertToModelMessages`, `streamText`, `tool`, `stepCountIs`, `UIMessage`).
- **`server.ts`** — server-side helpers: `normalizeWidgetMessages()` and `convertWidgetMessagesToModelMessages()`. Used in backends to convert widget message format (data URLs for attachments) into model-compatible format.
- **`theme.ts`** — CSS variable generation for theming.
- **`components/`** — UI layer: `WidgetPanel`, `MessageList`, `Composer`, `ChatToggleButton`, `MarkdownMessage`, `EmptyState`, `ReasoningPanel`.
- **`components/ai-elements/`** — AI-specific rendering: `Conversation`, `Message`, `Response`, `Reasoning`, `Tool`, `Confirmation`, `PromptInput`. The `Tool` component handles the full tool lifecycle (pending → approval-requested → approved/denied → output).
- **`utils/chat.ts`** — type guards and extractors for `UIMessage` parts (`isTextPart`, `isReasoningPart`, `isToolPart`, `extractRenderableUserText`, `extractRenderableUserFiles`, etc.).

### Sandbox (`sdk/sandbox/`)

Used only for local development. The Hono server in `sandbox/server/index.ts` implements example agent routes (default + notion). The Vite app in `sandbox/src/App.tsx` mounts `<OpenChatWidget>` against those routes.

### Examples (`examples/`)

Standalone apps (not npm-linked). Each demonstrates a pattern:
- `basic-react-express-app/` — Vite React frontend + Express backend
- `nextjs-landing-page/` — Next.js with OpenRouter
- `nextjs-portfolio-chat/` — Next.js portfolio chat

### Docs (`docs/`)

Mintlify documentation site (`.mdx` files). To run locally: `npm install -g mint && mint dev`.

## Key Patterns

**Adding a backend agent**: Implement an HTTP endpoint that accepts POST with `UIMessage[]`, calls `convertWidgetMessagesToModelMessages()` on the body, pipes through `streamText`, and returns `result.toDataStreamResponse()`. Pass the URL to `<OpenChatWidget url="...">`.

**Tool lifecycle in the UI**: Tools flow through states tracked in `UIMessage` parts — `approval-requested` triggers a `Confirmation` dialog; user approval/denial is sent back; `output-available` or `output-error` renders the result. See `sdk/widget/src/components/ai-elements/Tool.tsx` and `utils/chat.ts`.

**Theming**: `buildOpenChatWidgetThemeCss()` in `theme.ts` generates CSS custom properties injected into the widget's shadow DOM at runtime.
