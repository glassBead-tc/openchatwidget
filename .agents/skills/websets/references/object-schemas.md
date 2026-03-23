# Exa Websets — Object Schemas Reference

## Webset
```json
{
  "id": "ws_abc123",
  "object": "webset",
  "status": "idle",
  "externalId": "my-unique-id",
  "searches": [WebsetSearch],
  "enrichments": [WebsetEnrichment],
  "metadata": {},
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:05:00Z"
}
```
**Status values:** `running` | `idle` | `paused`

## WebsetSearch
```json
{
  "id": "ws_search_abc",
  "object": "webset_search",
  "status": "completed",
  "query": "AI companies in Europe",
  "entity": {"type": "company"},
  "criteria": [
    {"description": "Company is an AI startup", "successRate": 85.5}
  ],
  "count": 50,
  "progress": {"found": 42, "completion": 100.0},
  "metadata": {},
  "canceledAt": null,
  "canceledReason": null,
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:05:00Z"
}
```
**Status:** `created` | `running` | `completed` | `canceled`
**Canceled reasons:** `webset_deleted` | `webset_canceled`

## WebsetItem (full example)
```json
{
  "id": "wsi_abc123",
  "object": "webset_item",
  "source": "search",
  "sourceId": "ws_search_abc",
  "websetId": "ws_abc123",
  "properties": {
    "type": "company",
    "url": "https://example.com",
    "description": "An AI company focused on NLP",
    "content": "Full text content...",
    "company": {
      "name": "Example AI",
      "location": "London, UK",
      "employees": 150,
      "industry": "Artificial Intelligence",
      "about": "Example AI builds NLP tools.",
      "logoUrl": "https://example.com/logo.png"
    }
  },
  "evaluations": [
    {
      "criterion": "Company is an AI startup",
      "reasoning": "Website describes AI-powered products...",
      "satisfied": "yes",
      "references": [
        {"title": "About", "snippet": "We build AI tools...", "url": "https://example.com/about"}
      ]
    }
  ],
  "enrichments": [
    {
      "object": "enrichment_result",
      "enrichmentId": "enr_abc123",
      "format": "text",
      "result": ["Jane Smith"],
      "reasoning": "Found CEO on leadership page.",
      "references": [
        {"title": "Leadership", "url": "https://example.com/team"}
      ]
    }
  ],
  "createdAt": "2024-01-15T10:02:00Z",
  "updatedAt": "2024-01-15T10:04:00Z"
}
```

## Item Properties By Entity Type

| Entity | Extra fields |
|--------|-------------|
| `company` | `company.name`, `company.location`, `company.employees`, `company.industry`, `company.about`, `company.logoUrl` |
| `person` | `person.name`, `person.location`, `person.position`, `person.pictureUrl` |
| `article` | `article.author`, `article.publishedAt`, `content` |
| `research_paper` | `researchPaper.author`, `researchPaper.publishedAt`, `content` |
| `custom` | `custom.author`, `custom.publishedAt`, `content` |

All types always have: `url`, `description`, `type`

## WebsetEnrichment
```json
{
  "id": "enr_abc123",
  "object": "webset_enrichment",
  "status": "completed",
  "websetId": "ws_abc123",
  "title": "CEO Name",
  "description": "Find the CEO name",
  "format": "text",
  "options": null,
  "metadata": {},
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:05:00Z"
}
```
**Status:** `pending` | `completed` | `canceled`
**Formats:** `text` | `number` | `date` | `url` | `email` | `phone` | `options`

When `format = "options"`, `options` is an array of `{"label": "string"}` (max 20).

## EnrichmentResult (on each item)
```json
{
  "object": "enrichment_result",
  "enrichmentId": "enr_abc123",
  "format": "text",
  "result": ["Jane Smith"],
  "reasoning": "Found on the leadership page",
  "references": [
    {"title": "Team Page", "snippet": "Jane Smith, CEO", "url": "https://..."}
  ]
}
```
`result` is **always** `list[str]` or `null` — even for numbers, dates, etc.

## Evaluation (on each item)
```json
{
  "criterion": "Company is an AI startup",
  "reasoning": "Website describes AI-powered products...",
  "satisfied": "yes",
  "references": [{"title": "...", "snippet": "...", "url": "..."}]
}
```
`satisfied`: `"yes"` | `"no"` | `"unclear"`

## Webhook
```json
{
  "id": "wh_abc123",
  "object": "webhook",
  "status": "active",
  "url": "https://your-server.com/webhook",
  "events": ["webset.item.created", "webset.idle"],
  "secret": "whsec_...",
  "metadata": {},
  "createdAt": "2024-01-15T10:00:00Z",
  "updatedAt": "2024-01-15T10:00:00Z"
}
```
**Status:** `active` | `inactive`
**`secret` is ONLY returned on creation.**

## Pagination (all list endpoints)
```json
{
  "data": [...],
  "hasMore": true,
  "nextCursor": "cursor_abc123"
}
```
Python SDK: `page.has_more`, `page.next_cursor`
JavaScript SDK: `page.hasMore`, `page.nextCursor`