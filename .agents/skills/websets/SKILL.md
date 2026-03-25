---
name: exa-websets
description: >
  Build async-native Exa Websets servers and pipelines in Python or TypeScript. Use this skill
  whenever the user mentions Websets, Exa search at scale, async web data pipelines, structured
  enrichment, semantic cron/monitors, scheduled web intelligence, or building an MCP server that
  wraps the Websets API. Also triggers when the user wants to: create/manage a Webset, run
  enrichments, set up monitors for recurring search, handle Websets webhooks, import URLs for
  enrichment, or export structured item data. Covers the full lifecycle: create → poll/webhook →
  items → enrich → monitor → export.
---

# Exa Websets Skill

Comprehensive guide for building async-native Websets servers and pipelines.

## Base URL & Auth

```
Base URL: https://api.exa.ai/websets/v0
Auth header: x-api-key: {EXA_API_KEY}
```

Install:
```bash
pip install exa-py    # Python
npm install exa-js    # JavaScript
```

---

## Core Mental Model

Websets is **async-first**. Nothing returns results immediately.

```
POST /websets/          → creates webset (status: running)
  └─ WebsetSearch       → finds + verifies items (seconds to minutes)
       └─ WebsetItem    → each matched result, with evaluations
            └─ Enrichment → additional data extraction per item
                 └─ webset.idle event / status: idle → done
```

**Key invariants to never forget:**
- Items are nested under `properties`: `item.properties.url`, `item.properties.company.name`
- Enrichment results are always `list[str]` or `null` — even for numbers/dates
- Enrichment results have `enrichmentId`, not description — build a map: `{e.id: e.description for e in webset.enrichments}`
- Webhook `secret` is shown **only once** at creation — store it immediately
- Searches run sequentially with each other, but in parallel with enrichments
- Monitor cron triggers at most once per day (system constraint)

---

## Quickstart Pattern (Python)

```python
import asyncio
from exa_py import Exa
from exa_py.websets.types import CreateWebsetParameters, CreateEnrichmentParameters
import os

exa = Exa(os.getenv("EXA_API_KEY"))

# 1. Create
webset = exa.websets.create(
    params=CreateWebsetParameters(
        search={
            "query": "AI startups in regulated industries that raised Series A",
            "count": 25,
            "criteria": [
                {"description": "Company operates in a regulated industry (health, finance, legal)"},
                {"description": "Company has raised Series A funding"},
            ],
            "entity": {"type": "company"},
        },
        enrichments=[
            CreateEnrichmentParameters(description="CEO name", format="text"),
            CreateEnrichmentParameters(description="Founding year", format="number"),
            CreateEnrichmentParameters(
                description="Primary industry vertical",
                format="options",
                options=[{"label": "Healthcare"}, {"label": "Finance"}, {"label": "Legal"}, {"label": "Other"}]
            ),
        ],
        metadata={"project": "kastalien-research"}
    )
)

print(f"Webset: {webset.id}")
print(f"Dashboard: {webset.dashboard_url}")

# 2. Wait (blocking) — SDK polls internally
webset = exa.websets.wait_until_idle(webset.id)  # default timeout=3600s, poll_interval=5s

# 3. Collect — resolve enrichment ID → description
desc_map = {e.id: e.description for e in webset.enrichments}

cursor = None
while True:
    page = exa.websets.items.list(webset_id=webset.id, cursor=cursor)
    for item in page.data:
        print(item.properties.url)
        if item.properties.company:
            print(item.properties.company.name)
        for enr in item.enrichments:
            print(f"  {desc_map[enr.enrichment_id]}: {enr.result}")
    if not page.has_more:   # snake_case!
        break
    cursor = page.next_cursor
```

---

## Async-Native Pattern (aiohttp / httpx)

For MCP server contexts where you want non-blocking I/O:

```python
import asyncio
import httpx
import os

EXA_BASE = "https://api.exa.ai/websets/v0"
HEADERS = {"x-api-key": os.getenv("EXA_API_KEY"), "Content-Type": "application/json"}

async def create_webset(client: httpx.AsyncClient, payload: dict) -> dict:
    r = await client.post(f"{EXA_BASE}/websets/", json=payload, headers=HEADERS)
    r.raise_for_status()
    return r.json()

async def poll_until_idle(client: httpx.AsyncClient, webset_id: str,
                          poll_interval: float = 5.0, timeout: float = 3600.0) -> dict:
    import time
    start = time.monotonic()
    while True:
        r = await client.get(f"{EXA_BASE}/websets/{webset_id}", headers=HEADERS)
        r.raise_for_status()
        ws = r.json()
        if ws["status"] == "idle":
            return ws
        if time.monotonic() - start > timeout:
            raise TimeoutError(f"Webset {webset_id} did not idle within {timeout}s")
        await asyncio.sleep(poll_interval)

async def list_all_items(client: httpx.AsyncClient, webset_id: str) -> list[dict]:
    items, cursor = [], None
    while True:
        params = {"limit": 100}
        if cursor:
            params["cursor"] = cursor
        r = await client.get(f"{EXA_BASE}/websets/{webset_id}/items",
                             params=params, headers=HEADERS)
        r.raise_for_status()
        page = r.json()
        items.extend(page["data"])
        if not page["hasMore"]:
            break
        cursor = page["nextCursor"]
    return items
```

---

## Create Webset — Full Request Shape

```json
{
  "search": {
    "query": "string (required, min 1 char — any URL in query gets crawled as context)",
    "count": 10,
    "criteria": [
      {"description": "Verification rule (max 5)"}
    ],
    "entity": {"type": "company"},
    "behaviour": "override",
    "metadata": {}
  },
  "enrichments": [
    {
      "description": "What to extract (required)",
      "format": "text | number | date | url | email | phone | options",
      "options": [{"label": "Option A"}, {"label": "Option B"}],
      "metadata": {}
    }
  ],
  "externalId": "your-idempotency-key",
  "metadata": {}
}
```

**Entity types:** `company` | `person` | `article` | `research_paper` | `custom`
- For custom: `{"type": "custom", "description": "Job Postings"}`
- Omit to auto-detect (works well)

**`externalId`:** Idempotency key. Returns 409 on duplicate. Can be used as `{id}` in all subsequent calls.

---

## Adding Searches & Enrichments to Existing Websets

```python
# Add another search to same webset
search = exa.websets.searches.create(
    webset_id=webset.id,
    params={"query": "AI companies in Asia with Series B", "count": 25}
)

# Add enrichment after creation (applies to all existing + future items)
enrichment = exa.websets.enrichments.create(
    webset_id=webset.id,
    params=CreateEnrichmentParameters(description="LinkedIn URL", format="url")
)

# Check search progress
search_status = exa.websets.searches.get(webset.id, search.id)
print(search_status.progress.found, search_status.progress.completion)  # count, 0-100%
```

---

## Monitors (Semantic Cron)

Monitors run searches on a schedule — ideal for "semantic cron" / self-updating datasets:

```python
monitor = exa.websets.monitors.create(params={
    "websetId": webset.id,
    "cadence": {
        "cron": "0 9 * * 1",           # Mondays at 9am
        "timezone": "America/New_York"  # IANA timezone
    },
    "behavior": {
        "type": "search",              # or "refresh" to re-process existing items
        "config": {
            "parameters": {
                "query": "AI regulation news in the last week",
                "count": 10,
                "criteria": [{"description": "Article is about AI regulation"}],
                "entity": {"type": "article"},
                "behavior": "append"   # add new items, don't replace
            }
        }
    }
})
```

**Cadence constraint:** Triggers at most once per day regardless of cron expression.
**Behavior types:**
- `search`: find new items matching query
- `refresh`: re-run enrichments on existing items

---

## Webhooks

```python
# Create — secret shown ONCE, store immediately
webhook = exa.websets.webhooks.create(params={
    "url": "https://your-server.com/webhook",
    "events": ["webset.item.created", "webset.idle"],
    "metadata": {"env": "production"}
})
secret = webhook.secret  # store this NOW

# Signature verification
import hmac, hashlib

def verify_exa_webhook(payload: bytes, signature_header: str, secret: str) -> bool:
    parts = dict(p.split("=", 1) for p in signature_header.split(","))
    signed_payload = f"{parts['t']}.{payload.decode()}".encode()
    computed = hmac.new(secret.encode(), signed_payload, hashlib.sha256).hexdigest()
    return hmac.compare_digest(computed, parts["v1"])
```

**Available events:** See `references/events.md` for full list with data shapes.

**Key events for most pipelines:**
| Event | When |
|-------|------|
| `webset.item.created` | New item passes verification |
| `webset.item.enriched` | Enrichment result arrives |
| `webset.idle` | All operations complete |
| `monitor.run.completed` | Scheduled run finishes |
| `import.completed` | URL import finishes |

---

## Imports (Bring Your Own URLs)

```python
import_obj = exa.websets.imports.create(params={
    "websetId": webset.id,
    "urls": ["https://example.com/a", "https://example.com/b"]
})
# Enrichments defined on the webset are automatically applied to imported items
```

---

## Exports

```python
export = exa.websets.exports.create(webset_id=webset.id, params={"format": "csv"})
# Poll until complete
while True:
    exp = exa.websets.exports.get(webset_id=webset.id, export_id=export.id)
    if exp.status == "completed":
        print(exp.download_url)
        break
    await asyncio.sleep(2)
```

---

## Item Schema Reference

Items are always accessed via `item.properties.*`:

```python
item.properties.url              # always present
item.properties.type             # "company" | "person" | "article" | "research_paper" | "custom"
item.properties.description      # relevance description
item.properties.content          # full page text (if crawled)

# Entity-specific (check type first)
item.properties.company.name
item.properties.company.location
item.properties.company.employees
item.properties.company.industry
item.properties.company.about
item.properties.person.name
item.properties.person.position
item.properties.article.author
item.properties.article.published_at
```

**Evaluations** (criteria verification):
```python
for ev in item.evaluations:
    print(ev.criterion, ev.satisfied, ev.reasoning)
    # satisfied: "yes" | "no" | "unclear"
```

**Enrichment results** (always array or null):
```python
for enr in item.enrichments:
    desc = desc_map[enr.enrichment_id]   # resolve ID → description
    val = enr.result                      # list[str] | null
    print(f"{desc}: {val[0] if val else 'not found'}")
```

---

## Preview (Test Queries Without Creating)

```python
# HTTP only — test before committing
import httpx
r = httpx.post(
    "https://api.exa.ai/websets/v0/websets/preview",
    json={"search": {"query": "your query", "count": 5}},
    headers=HEADERS
)
print(r.json())
```

---

## Pagination Pattern

All list endpoints return:
```json
{"data": [...], "hasMore": true, "nextCursor": "cursor_abc"}
```

Python SDK uses `snake_case`: `page.has_more`, `page.next_cursor`
JavaScript SDK uses `camelCase`: `page.hasMore`, `page.nextCursor`

---

## Common Pitfalls

| Mistake | Fix |
|---------|-----|
| `item.url` | Use `item.properties.url` |
| `enr.description` | Use `desc_map[enr.enrichment_id]` |
| `enr.result` as string | It's always `list[str]` or `null` |
| `page.hasMore` in Python | Use `page.has_more` (snake_case) |
| Storing webhook secret later | Store `webhook.secret` immediately — only shown once |
| Expecting sync results | Websets is always async — poll or use webhooks |
| Multiple enrichment formats in one | `options` format requires `options` array with 1–20 `{"label": "..."}` items |
| Monitor running hourly | Cron triggers at most once per day |

---

## MCP Server Pattern

For Thoughtbox/MCP server wrapping Websets:

```python
from mcp.server.fastmcp import FastMCP
from exa_py import Exa
import os

mcp = FastMCP("websets-server")
exa = Exa(os.getenv("EXA_API_KEY"))

@mcp.tool()
async def create_webset_search(query: str, count: int = 10,
                                entity_type: str = "company") -> dict:
    """Create a Webset search and return the webset ID for polling."""
    webset = exa.websets.create(params={
        "search": {"query": query, "count": count,
                   "entity": {"type": entity_type}}
    })
    return {"webset_id": webset.id, "status": webset.status,
            "dashboard_url": webset.dashboard_url}

@mcp.tool()
async def get_webset_items(webset_id: str, wait: bool = False) -> dict:
    """Get items from a Webset. Set wait=True to block until idle."""
    if wait:
        webset = exa.websets.wait_until_idle(webset_id)
    desc_map = {}
    ws = exa.websets.get(webset_id)
    desc_map = {e.id: e.description for e in ws.enrichments}
    page = exa.websets.items.list(webset_id=webset_id)
    return {
        "status": ws.status,
        "items": [
            {
                "url": item.properties.url,
                "type": item.properties.type,
                "enrichments": {
                    desc_map.get(enr.enrichment_id, enr.enrichment_id): enr.result
                    for enr in item.enrichments
                }
            }
            for item in page.data
        ]
    }
```

---

## Further Reference

- `references/events.md` — Full event types table with data shapes
- `references/object-schemas.md` — Complete JSON schemas for all objects
- Full API docs: https://exa.ai/docs/websets/api/overview
- Coding agent guide: https://exa.ai/docs/websets/api-guide-for-coding-agents