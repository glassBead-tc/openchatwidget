# Exa Websets Dashboard UI Reference

Crawled from exa.ai/docs/websets/dashboard/* on 2026-03-23. Use as the design
reference for the MCP App UI.

Source: https://websets.exa.ai / https://exa.ai/docs/websets/dashboard

---

## Global Layout

```
+-------+------------------------------------------------------------+
| Side  |  Main Content Area                                         |
| bar   |                                                            |
|       |                                                            |
| (col- |  [Toolbar / action bar]                                    |
| laps- |  [Content view: table, detail, or search input]            |
| ible) |                                                            |
|       |                                                            |
+-------+------------------------------------------------------------+
```

- **Sidebar (left)**: Collapsible via top-left hamburger icon. Shows full
  history of all past Websets as a scrollable list. Each entry shows webset
  title. Clicking navigates to that webset's results view.
- **Main content**: Fills remaining width. Content depends on current view.

---

## Views & Flows

### 1. Search / Create View (Landing)

The initial view when visiting websets.exa.ai.

- **Plain English input field**: Large text area where users describe what
  they want (e.g. "AI startups in San Francisco founded after 2020")
- Users can make requests as complex as they want
- Integrated chat component for iterating on criteria with an AI agent

### 2. Confirmation / Preview Screen

After entering a query:

- **Criteria preview**: Shows the parsed criteria as a checklist
- **Data category selector**: Entity type (company, person, article, etc.)
- **Result quantity selector**: How many results to fetch
- **"Start your search" button**: Primary action

### 3. Processing View

While the webset is being built:

Four sequential operations displayed as progress:
1. Breaking down the request
2. Locating candidate data
3. Verifying criteria using AI agents across parallel sources
4. Refining based on feedback

### 4. Results Table View (Primary Data View)

The main view once a webset has results.

```
+------------------------------------------------------------------+
| Webset Title                          [Export CSV] [Share] [Edit] |
+------------------------------------------------------------------+
| Search: "AI startups in SF"           Status: idle   Found: 100  |
+------------------------------------------------------------------+
|  Name/Title  | Summary      | Criteria | Enrichment1 | Enrich2  |
|------------- |------------- |----------|-------------|----------|
|  Company A   | AI-gen text  | 3/3 met  | $5M rev     | seed     |
|  Company B   | AI-gen text  | 2/3 met  | $12M rev    | series A |
|  Company C   | AI-gen text  | 3/3 met  | N/A         | seed     |
+------------------------------------------------------------------+
| Showing 1-50 of 100                              [< Prev] [Next >]|
+------------------------------------------------------------------+
```

Key elements:
- **Title bar**: Webset title (auto-generated), action buttons (Export CSV,
  Share link, Edit criteria)
- **Status bar**: Search query text, status badge (idle/processing), result
  count
- **Data table**: Columns for entity name, AI-generated summary, criteria
  match indicators, and enrichment columns
- **Clickable rows**: Clicking a result opens the detail panel
- **Delete per row**: Manual deletion capability
- **Pagination**: Standard prev/next with count display

### 5. Result Detail Panel

Clicking a result row opens a detail view (likely a side panel or expanded row):

- **AI-generated summary**: Full text summary of the entity
- **Criteria matched**: Checklist showing which criteria were met
- **Source citations**: Clickable links to the sources that informed the match
- **Enrichment values**: All enrichment data for this item

### 6. Enrichment Management

Accessible from the results view:

- **"Add enrichments" button**: Opens enrichment creation form
- **Enrichment creation form**:
  - Column name text input
  - Column type dropdown: text, number, date, email, phone, url, options
  - Instructions text area (describe what data to extract)
  - "Fill in for me" button (auto-generate instructions)
- Enrichment columns appear as new columns in the results table
- Each enrichment shows status (pending/completed) per item

### 7. Sidebar / History

- Full history of all past websets
- Each entry: webset title, entity type badge, status indicator
- Click to navigate to that webset
- Chronological ordering (most recent first)

---

## Visual Design Patterns

### Color Scheme
- Clean, modern SaaS aesthetic
- Light background with subtle borders
- Status badges: idle (green/neutral), processing (blue/animated), error (red)
- Primary action buttons: solid fill (likely blue/purple brand color)
- Secondary actions: outlined or text-only

### Typography
- Sans-serif font family (likely Inter or similar)
- Webset titles: bold, larger
- Table headers: semi-bold, uppercase or small-caps
- Body text: regular weight

### Component Patterns
- **Cards/rows**: Subtle borders, hover highlighting
- **Badges**: Rounded pills for status, entity type
- **Buttons**: Rounded corners, icon + text for primary actions
- **Tables**: Alternating row backgrounds or clean lines
- **Sidebar**: Dark or slightly contrasted background vs main content

---

## Data Model → UI Mapping

| API Entity     | UI Representation                                    |
|---------------|------------------------------------------------------|
| Webset        | List item in sidebar + full results view             |
| Search        | Status bar within webset view, query text displayed  |
| Item          | Table row with summary, criteria, enrichment columns |
| Enrichment    | Column in results table + creation form              |
| Monitor       | Settings panel (cron schedule, behavior)             |
| Webhook       | Settings panel (URL, events, delivery attempts)      |
| Import        | Upload interface or URL list input                   |
| Event         | Activity log / timeline view                         |
| Task          | Progress indicator with status                       |
| Research      | Separate results pane with markdown output           |

---

## Key Interactions for MCP App

The MCP App should prioritize these views in order of importance:

1. **Webset list** — sidebar/overview of all websets with status
2. **Results table** — the primary data table with items + enrichment columns
3. **Item detail** — expandable detail view per item
4. **Task/progress** — status indicators for running tasks/searches
5. **Search/create** — query input for creating new websets (lower priority
   since the agent handles creation via tools)

The enrichment creation form and monitor/webhook management can remain
tool-only (no UI needed) since they're configuration operations best handled
by the agent.
