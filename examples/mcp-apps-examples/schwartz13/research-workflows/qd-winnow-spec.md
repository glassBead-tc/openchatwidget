# QD Winnowing Workflow — Implementation Specification

**File**: `src/workflows/qdWinnow.ts`
**Task type**: `qd.winnow`
**Depends on**: Phase 1+2 complete (TaskStore, workflow registry, research handlers)
**Tracking**: `searchbox-ewn` Phase 3

---

## 1. Overview

Quality-Diversity winnowing uses Websets criteria as behavioral coordinates and enrichments as fitness functions. The workflow creates a webset, waits for search completion, collects items, classifies them into niches by criteria satisfaction, scores fitness from enrichments, selects elites (best per niche), and returns structured metrics.

This is the foundational composite workflow — `lifecycle.harvest` and `convergent.search` are special cases.

---

## 2. Task Args

```typescript
{
  type: 'qd.winnow',
  // Required
  query: string,                               // search query
  entity: { type: string },                    // 'company' | 'person' | etc.
  criteria: Array<{ description: string }>,    // behavioral coordinates (1-10)

  // Required — at least 1 enrichment for fitness scoring
  enrichments: Array<{
    description: string,
    format?: 'text' | 'number' | 'options' | 'url' | 'date' | 'email' | 'phone',
    options?: Array<{ label: string }>,
  }>,

  // Optional
  count?: number,                  // search result count, default 50
  seedWebsetId?: string,           // append to existing webset instead of creating new
  timeout?: number,                // per-step timeout in ms, default 300_000 (5 min)
  critique?: boolean,              // call Research API to evaluate results, default false
  selectionStrategy?: 'all-criteria' | 'any-criteria' | 'diverse',  // default 'diverse'
}
```

**Validation** (in workflow, before any API calls):
- `criteria` required, non-empty, max 10
- `enrichments` required, non-empty
- `query` required unless `seedWebsetId` provided
- If `selectionStrategy` not recognized, default to `'diverse'`

---

## 3. SDK Types (Ground Truth)

These are the actual shapes from `exa-js` SDK that the workflow must handle.

### WebsetItem.evaluations[]

```typescript
{
  criterion: string,         // the description text
  satisfied: "yes" | "no" | "unclear",
  reasoning: string,
  references: Array<{ url: string, title: string | null, snippet: string | null }>,
}
```

### WebsetItem.enrichments[]

```typescript
{
  enrichmentId: string,
  format: "text" | "date" | "number" | "options" | "email" | "phone" | "url",
  result: string[] | null,   // always string array, even for number format
  status: "pending" | "completed" | "canceled",
  reasoning: string | null,
  references: Array<{ url: string, title: string | null, snippet: string | null }>,
  object: "enrichment_result",
}
```

### WebsetSearch.progress

```typescript
{
  found: number,
  analyzed: number,
  completion: number,     // 0-100 percentage
  timeLeft: number | null,
}
```

### WebsetSearch.criteria[]

```typescript
{
  description: string,
  successRate: number,    // 0-100 — percentage of analyzed items that satisfy
}
```

**Key observations**:
- `satisfied` has 3 values: `"yes"`, `"no"`, `"unclear"` — treat `"unclear"` as `false` for niche classification
- No `boolean` enrichment format exists in the SDK (the spec was wrong) — formats are: text, date, number, options, email, phone, url
- `enrichment.result` is `string[] | null` even for number format — must parse
- `enrichment.status` can be `"pending"` or `"canceled"` — skip these for fitness scoring
- `successRate` on criteria is 0-100 (not 0-1) — the descriptor feedback threshold math uses this directly

---

## 4. Workflow Steps

### Step 0: Validate & Initialize

```
- Validate args (criteria, enrichments, query/seedWebsetId)
- store.updateProgress(taskId, { step: 'initializing', completed: 0, total: 7 })
- Check cancellation before each subsequent step
```

### Step 1: Create or Append to Webset

**New webset** (no `seedWebsetId`):
```typescript
exa.websets.create({
  search: {
    query: args.query,
    count: args.count ?? 50,
    criteria: args.criteria,
    entity: args.entity,
  },
  enrichments: args.enrichments,
})
```

**Append to existing** (`seedWebsetId` provided):
```typescript
exa.websets.searches.create(args.seedWebsetId, {
  query: args.query,
  count: args.count ?? 50,
  criteria: args.criteria,
  entity: args.entity,
  behavior: 'append',  // required
})
// Then add enrichments if they aren't already on the webset
for (const enrichment of args.enrichments) {
  exa.websets.enrichments.create(args.seedWebsetId, enrichment)
}
```

**Progress**: `{ step: 'creating', completed: 1, total: 7 }`

### Step 2: Poll Until Idle

```typescript
exa.websets.waitUntilIdle(websetId, {
  timeout: args.timeout ?? 300_000,
  pollInterval: 2000,
})
```

During polling, update progress with search metrics. Use a custom polling loop instead of the SDK's `waitUntilIdle` so we can report progress:

```typescript
while (true) {
  const ws = await exa.websets.get(websetId)
  if (ws.status === 'idle') break
  if (ws.status === 'canceled') throw new Error('Webset was canceled')

  // Extract search progress
  const search = ws.searches[ws.searches.length - 1]
  if (search?.progress) {
    const stringency = search.progress.analyzed > 0
      ? search.progress.found / search.progress.analyzed
      : 0

    store.updateProgress(taskId, {
      step: 'searching',
      completed: 2,
      total: 7,
      message: `Found ${search.progress.found}/${search.progress.analyzed} analyzed (stringency: ${(stringency * 100).toFixed(1)}%)`,
    })
  }

  // Check cancellation
  if (store.get(taskId)?.status === 'cancelled') {
    await exa.websets.cancel(websetId)
    return null  // workflow runner won't call setResult
  }

  await sleep(2000)
}
```

**Progress**: `{ step: 'searching', completed: 2, total: 7, message: '...' }`

### Step 3: Collect Items

```typescript
const items: WebsetItem[] = []
for await (const item of exa.websets.items.listAll(websetId)) {
  items.push(item)
  if (items.length >= 1000) break  // safety cap
}
```

**Progress**: `{ step: 'collecting', completed: 3, total: 7 }`

**Partial result checkpoint**: Set partial result with raw items before classification.

### Step 4: Classify Into Niches

For each item, build a criteria satisfaction vector from its `evaluations` array:

```typescript
function classifyItem(item: WebsetItem, criteriaDescs: string[]): { niche: string, vector: boolean[] } {
  const vector = criteriaDescs.map(desc => {
    const evaluation = item.evaluations.find(e => e.criterion === desc)
    return evaluation?.satisfied === 'yes'  // "no" and "unclear" both → false
  })
  const niche = vector.map(v => v ? '1' : '0').join(',')
  return { niche, vector }
}
```

**Niche key**: `"1,1,0"` = satisfies criteria 1 and 2, not 3. With N criteria → up to 2^N niches.

**Edge case**: If an item has no evaluations (e.g., from a prior search without criteria), all criteria → false. It lands in the "0,0,...,0" niche.

### Step 5: Score Fitness

For each item, compute fitness from its enrichment results:

```typescript
function scoreItem(item: WebsetItem): number {
  const completedEnrichments = (item.enrichments ?? [])
    .filter(e => e.status === 'completed' && e.result !== null)

  if (completedEnrichments.length === 0) return 0

  const scores = completedEnrichments.map(e => scoreEnrichment(e))
  return scores.reduce((a, b) => a + b, 0) / scores.length
}

function scoreEnrichment(e: EnrichmentResult): number {
  if (e.result === null || e.result.length === 0) return 0

  switch (e.format) {
    case 'number': {
      // result is string[] — parse first element
      const num = parseFloat(e.result[0])
      return isNaN(num) ? 0 : num
    }
    case 'options':
      // Has a selected option → 1, else 0
      return e.result.length > 0 ? 1 : 0
    case 'text':
    case 'date':
    case 'email':
    case 'phone':
    case 'url':
      // Presence-based: has content → 1, else 0
      return e.result.length > 0 && e.result[0].length > 0 ? 1 : 0
    default:
      return 0
  }
}
```

**Number normalization**: For v1, raw number scores are used. Cross-item normalization (min-max scaling) can be added in v2 if needed, but adds complexity for questionable benefit when most enrichments are presence-based.

**Progress**: `{ step: 'scoring', completed: 5, total: 7 }`

### Step 6: Select Elites

Group items by niche, pick the highest-fitness item per niche:

```typescript
type ClassifiedItem = {
  item: WebsetItem,
  niche: string,
  criteriaVector: boolean[],
  fitnessScore: number,
}

function selectElites(
  classified: ClassifiedItem[],
  strategy: 'all-criteria' | 'any-criteria' | 'diverse',
): ClassifiedItem[] {
  switch (strategy) {
    case 'all-criteria': {
      // Only items that satisfy ALL criteria
      const fullNiche = classified[0]?.criteriaVector.map(() => true)
      const fullKey = fullNiche?.map(v => v ? '1' : '0').join(',')
      return classified
        .filter(c => c.niche === fullKey)
        .sort((a, b) => b.fitnessScore - a.fitnessScore)
    }
    case 'any-criteria': {
      // All items that satisfy at least one criterion, sorted by fitness
      const zeroKey = classified[0]?.criteriaVector.map(() => '0').join(',')
      return classified
        .filter(c => c.niche !== zeroKey)
        .sort((a, b) => b.fitnessScore - a.fitnessScore)
    }
    case 'diverse':
    default: {
      // Best per niche (MAP-Elites style)
      const niches = new Map<string, ClassifiedItem>()
      for (const c of classified) {
        const existing = niches.get(c.niche)
        if (!existing || c.fitnessScore > existing.fitnessScore) {
          niches.set(c.niche, c)
        }
      }
      return [...niches.values()].sort((a, b) => b.fitnessScore - a.fitnessScore)
    }
  }
}
```

### Step 7: Compute Metrics + Descriptor Feedback

```typescript
const numCriteria = args.criteria.length
const possibleNiches = Math.pow(2, numCriteria)
const populatedNiches = new Set(classified.map(c => c.niche)).size

// Niche distribution: niche key → count
const nicheDistribution: Record<string, number> = {}
for (const c of classified) {
  nicheDistribution[c.niche] = (nicheDistribution[c.niche] ?? 0) + 1
}

// Shannon entropy for diversity
const total = classified.length
const entropy = Object.values(nicheDistribution).reduce((sum, count) => {
  const p = count / total
  return sum - (p > 0 ? p * Math.log2(p) : 0)
}, 0)
const maxEntropy = Math.log2(possibleNiches)
const diversity = maxEntropy > 0 ? entropy / maxEntropy : 0  // normalized 0-1

// Stringency from last search progress
const lastSearch = webset.searches[webset.searches.length - 1]
const stringency = lastSearch?.progress
  ? lastSearch.progress.found / Math.max(lastSearch.progress.analyzed, 1)
  : 0

// Descriptor feedback from search criteria successRates
const descriptorFeedback = (lastSearch?.criteria ?? []).map(c => ({
  criterion: c.description,
  successRate: c.successRate,  // 0-100
  quality: c.successRate < 5 ? 'too-strict' as const
    : c.successRate > 95 ? 'not-discriminating' as const
    : 'good-discriminator' as const,
}))

const qualityMetrics = {
  coverage: populatedNiches / possibleNiches,
  avgFitness: elites.length > 0
    ? elites.reduce((s, e) => s + e.fitnessScore, 0) / elites.length
    : 0,
  diversity,
  stringency,
}
```

### Step 8 (Optional): Critique via Research API

If `args.critique === true`:

```typescript
const critiqueInstructions = `Given the research query "${args.query}" targeting ${args.entity.type} entities, and ${items.length} results classified into ${populatedNiches} niches:

Top elites:
${elites.slice(0, 10).map(e => `- [${e.niche}] fitness=${e.fitnessScore.toFixed(2)}: ${summarizeItem(e.item)}`).join('\n')}

Quality metrics: coverage=${qualityMetrics.coverage.toFixed(2)}, avgFitness=${qualityMetrics.avgFitness.toFixed(2)}, diversity=${diversity.toFixed(2)}, stringency=${stringency.toFixed(3)}

Assess:
1. Coverage: are important entity types/niches missing?
2. Quality: are the top results genuinely relevant?
3. Gaps: what blind spots exist in the criteria?
4. Surprises: anything unexpected that deserves deeper investigation?`

const research = await exa.research.create({
  instructions: critiqueInstructions,
  model: 'exa-research-fast',
})
const critiqueResult = await exa.research.pollUntilFinished(research.researchId, {
  timeoutMs: 120_000,
})
```

`summarizeItem` extracts a brief label from item properties (name/title + url).

---

## 5. Task Result Shape

```typescript
{
  websetId: string,
  itemCount: number,

  nicheDistribution: Record<string, number>,  // "1,1,0" → count

  elites: Array<{
    item: WebsetItem,        // full item object
    niche: string,           // "1,1,0"
    criteriaVector: boolean[],
    fitnessScore: number,
  }>,

  qualityMetrics: {
    coverage: number,        // 0-1: populated niches / possible niches
    avgFitness: number,      // mean fitness across elites
    diversity: number,       // 0-1: normalized Shannon entropy
    stringency: number,      // 0-1: found/analyzed ratio
  },

  descriptorFeedback: Array<{
    criterion: string,
    successRate: number,     // 0-100
    quality: 'too-strict' | 'good-discriminator' | 'not-discriminating',
  }>,

  critique?: {
    researchId: string,
    content: string,         // Research API output text
  },

  duration: number,          // total ms
  steps: Array<{ name: string, durationMs: number }>,
}
```

---

## 6. Cancellation Protocol

Between every step (and during the polling loop), check:

```typescript
function isCancelled(taskId: string, store: TaskStore): boolean {
  const task = store.get(taskId)
  return task?.status === 'cancelled'
}
```

If cancelled:
- During search: cancel the webset via `exa.websets.cancel(websetId)`, set partial result
- After search: set partial result with whatever has been collected so far
- Return `null` from the workflow — the task handler won't overwrite the cancelled status

---

## 7. Error Handling

| Error | Recovery |
|-------|----------|
| Webset creation fails | Set error immediately, return |
| Search timeout (waitUntilIdle) | Collect whatever items exist, return partial result |
| No items found | Return result with empty elites, metrics all 0 |
| Item has no evaluations | Classify into "0,0,...,0" niche |
| Item has no enrichments | Fitness score = 0 |
| Enrichment status is "pending"/"canceled" | Skip for fitness scoring |
| Number enrichment can't be parsed | Score as 0 |
| Critique fails | Include error in result, don't fail the whole workflow |
| Rate limit (429) | The SDK handles retries internally; if persistent, let error propagate |

---

## 8. Helper: summarizeItem

```typescript
function summarizeItem(item: WebsetItem): string {
  const props = item.properties as Record<string, unknown>
  const name = (props.name ?? props.title ?? props.company?.name ?? 'unknown') as string
  const url = (props.url ?? '') as string
  return url ? `${name} (${url})` : name
}
```

---

## 9. File Structure

```
src/workflows/qdWinnow.ts     — Main workflow + helper functions
```

All helpers (`classifyItem`, `scoreItem`, `scoreEnrichment`, `selectElites`, `computeMetrics`, `summarizeItem`) are module-private functions in the same file. No reason to extract them — they're specific to this workflow and easier to test through the workflow's integration test.

---

## 10. Registration

In `src/workflows/qdWinnow.ts`, at module level:

```typescript
import { registerWorkflow } from './types.js';

registerWorkflow('qd.winnow', qdWinnowWorkflow);
```

Side-effect import in `src/tools/manageWebsets.ts`:

```typescript
import '../workflows/qdWinnow.js';
```

---

## 11. Tests

### Unit Tests (`src/workflows/__tests__/qdWinnow.test.ts`)

Mock the Exa client to return controlled item data and test:

1. **Niche classification**: Items with known evaluations → correct niche keys
2. **Fitness scoring**: Items with known enrichment results → correct scores
   - Number format: `result: ["42.5"]` → 42.5
   - Options format: `result: ["Series A"]` → 1
   - Text format: `result: ["some text"]` → 1
   - Null/empty result → 0
   - Pending enrichment → skipped
3. **Elite selection — diverse**: 3 niches, picks best per niche
4. **Elite selection — all-criteria**: Only full-satisfaction niche returned
5. **Elite selection — any-criteria**: Zero-niche excluded
6. **Quality metrics**: Known distribution → correct coverage, entropy, stringency
7. **Descriptor feedback**: Known successRates → correct quality labels
8. **Full workflow**: Mock exa to return webset, items, then verify complete result shape

### Integration Test (`src/workflows/__tests__/integration/qdWinnow.test.ts`)

Gated on `HAS_API_KEY`. Create a real qd.winnow task with:
- query: "AI safety research organizations"
- entity: { type: "company" }
- criteria: [{ description: "Founded after 2015" }, { description: "Has published peer-reviewed research" }]
- enrichments: [{ description: "Number of employees", format: "number" }]
- count: 10

Then poll `tasks.get` until completed, verify result has niches, elites, metrics.

---

## 12. Open Questions Resolved

| Question | Resolution |
|----------|-----------|
| No `boolean` enrichment format | SDK only has: text, date, number, options, email, phone, url. Spec was wrong. Use presence-based scoring for non-number formats. |
| `satisfied: "unclear"` | Treat as `false` for niche classification. Item goes to the "didn't satisfy" side of that criterion. |
| `enrichment.result` type | Always `string[] \| null`, even for numbers. Must parse. |
| Number normalization | Skip for v1. Raw numbers used. Most fitness is presence-based anyway. |
| Multi-round iteration | v1 is single-round (`maxRounds` not implemented). Agent-driven iteration via `seedWebsetId`. |
| Result size | Cap at 1000 items. Elites are typically much fewer (2^N niches max). |
