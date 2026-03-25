# Exa Websets — Event Types Reference

All events are retained for 60 days.

## Event Shape
```json
{
  "id": "evt_abc123",
  "object": "event",
  "type": "webset.item.created",
  "data": { ... },
  "createdAt": "2024-01-15T10:02:00Z"
}
```

## Full Event Table

| Event | Fires When | `data` contains |
|-------|-----------|-----------------|
| `webset.created` | Webset created | `Webset` |
| `webset.deleted` | Webset deleted | `Webset` |
| `webset.paused` | Webset paused | `Webset` |
| `webset.idle` | All searches + enrichments complete | `Webset` |
| `webset.search.created` | A search starts | `WebsetSearch` |
| `webset.search.updated` | Search progress update | `WebsetSearch` |
| `webset.search.completed` | A search finishes | `WebsetSearch` |
| `webset.search.canceled` | A search is canceled | `WebsetSearch` |
| `webset.item.created` | Item added (passed verification) | `WebsetItem` |
| `webset.item.enriched` | Enrichment result added to item | `WebsetItem` |
| `webset.export.created` | Export scheduled | Export |
| `webset.export.completed` | Export ready for download | Export |
| `import.created` | Import starts | Import |
| `import.completed` | Import finishes | Import |
| `monitor.created` | Monitor created | Monitor |
| `monitor.updated` | Monitor config updated | Monitor |
| `monitor.deleted` | Monitor deleted | Monitor |
| `monitor.run.created` | Scheduled run starts | MonitorRun |
| `monitor.run.completed` | Scheduled run finishes | MonitorRun |

## Webhook Subscription — Common Subsets

**Minimal pipeline (just get items):**
```json
["webset.item.created", "webset.idle"]
```

**Full observability:**
```json
[
  "webset.created", "webset.idle",
  "webset.search.created", "webset.search.completed",
  "webset.item.created", "webset.item.enriched"
]
```

**Monitor-driven pipeline:**
```json
["monitor.run.created", "monitor.run.completed", "webset.item.created"]
```

**Import pipeline:**
```json
["import.created", "import.completed", "webset.item.enriched"]
```

## Webhook Signature Verification

Header format: `Exa-Signature: t=1234567890,v1=abc123...`

```python
import hmac, hashlib

def verify_exa_webhook(raw_body: bytes, sig_header: str, secret: str) -> bool:
    parts = dict(p.split("=", 1) for p in sig_header.split(","))
    signed = f"{parts['t']}.{raw_body.decode()}".encode()
    computed = hmac.new(secret.encode(), signed, hashlib.sha256).hexdigest()
    return hmac.compare_digest(computed, parts["v1"])
```