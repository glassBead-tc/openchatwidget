-- Evaluation System Extension for the Agentic Dev Team
-- Extends the MAP-Elites schema in workflows.db with evaluation tables
--
-- Usage: sqlite3 research-workflows/workflows.db < research-workflows/evaluation-schema.sql
--
-- This schema adds evaluation tracking alongside the existing
-- workflows, workflow_steps, workflow_lineage, executions, and taste_evaluations tables.

-- Named collections of test cases, one per agent
CREATE TABLE IF NOT EXISTS eval_datasets (
    id TEXT PRIMARY KEY,                        -- dataset-{agent_name}-{version}
    agent_name TEXT NOT NULL,                   -- triage-fix, research-taste, etc.
    name TEXT NOT NULL,
    description TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    version INTEGER NOT NULL DEFAULT 1,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'archived')),
    example_count INTEGER NOT NULL DEFAULT 0,
    langsmith_dataset_id TEXT                   -- corresponding LangSmith dataset ID, if synced
);

-- Individual test cases (input, expected output, metadata)
CREATE TABLE IF NOT EXISTS eval_examples (
    id TEXT PRIMARY KEY,                        -- example-{uuid}
    dataset_id TEXT NOT NULL REFERENCES eval_datasets(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),

    -- The test case
    input TEXT NOT NULL,                        -- JSON: the scenario/input given to the agent
    reference_output TEXT,                      -- JSON: expected output (null for reference-free evals)
    context TEXT,                               -- JSON: additional context (files, config, environment)

    -- Metadata
    provenance TEXT NOT NULL,                   -- Where this example came from (e.g., "production-failure-2026-02-05", "manual-curation")
    difficulty TEXT CHECK (difficulty IN ('easy', 'medium', 'hard', 'adversarial')),
    category TEXT,                              -- Agent-specific category (e.g., "internal-bug", "external-dep" for triage-fix)
    tags TEXT,                                  -- Comma-separated tags for filtering
    notes TEXT,

    -- Tracking
    times_evaluated INTEGER NOT NULL DEFAULT 0,
    last_evaluated_at TEXT,
    langsmith_example_id TEXT                   -- corresponding LangSmith example ID, if synced
);

-- Registry of all graders (code-based, model-based, human)
CREATE TABLE IF NOT EXISTS eval_graders (
    id TEXT PRIMARY KEY,                        -- grader name (e.g., "triage_tests_pass")
    agent_name TEXT NOT NULL,                   -- which agent this grader evaluates
    grader_type TEXT NOT NULL CHECK (grader_type IN ('code', 'model', 'human', 'trajectory')),
    description TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),

    -- Configuration
    config TEXT,                                -- JSON: grader-specific config (e.g., judge prompt, script path)
    judge_model TEXT,                           -- For model-based: which model (e.g., "claude-haiku-4-5-20251001")
    judge_prompt TEXT,                          -- For model-based: the judge prompt template
    cost_estimate_usd REAL DEFAULT 0.0,         -- Estimated cost per evaluation

    -- Calibration tracking
    total_evaluations INTEGER NOT NULL DEFAULT 0,
    agreement_with_human REAL,                  -- Latest agreement rate with human graders (0-1)
    last_calibrated_at TEXT,

    -- Status
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'deprecated', 'untrusted'))
);

-- Batch evaluation runs (an experiment = running all graders on a dataset)
CREATE TABLE IF NOT EXISTS eval_experiments (
    id TEXT PRIMARY KEY,                        -- experiment-{uuid}
    dataset_id TEXT NOT NULL REFERENCES eval_datasets(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    completed_at TEXT,

    -- Experiment metadata
    agent_name TEXT NOT NULL,
    agent_version TEXT,                         -- Git hash or version tag of agent instructions
    description TEXT,                           -- Why this experiment was run
    trigger TEXT CHECK (trigger IN ('manual', 'regression', 'prompt-change', 'online')),

    -- Aggregate metrics
    total_examples INTEGER NOT NULL DEFAULT 0,
    total_passed INTEGER NOT NULL DEFAULT 0,
    total_failed INTEGER NOT NULL DEFAULT 0,
    pass_rate REAL,                             -- total_passed / total_examples

    -- pass@k / pass^k for capability vs reliability
    pass_at_k INTEGER,                          -- k value used
    pass_at_k_rate REAL,                        -- fraction that passed at least once in k runs
    pass_pow_k_rate REAL,                       -- fraction that passed all k runs

    -- Linked beads issue
    beads_issue_id TEXT,

    status TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running', 'completed', 'failed', 'cancelled'))
);

-- Individual grader results for specific examples in an experiment
CREATE TABLE IF NOT EXISTS eval_results (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    experiment_id TEXT NOT NULL REFERENCES eval_experiments(id) ON DELETE CASCADE,
    example_id TEXT NOT NULL REFERENCES eval_examples(id),
    grader_id TEXT NOT NULL REFERENCES eval_graders(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),

    -- The actual agent output being evaluated
    agent_output TEXT,                          -- JSON: what the agent actually produced

    -- Grader result
    score REAL,                                 -- Numeric score (0-1 for continuous, 0 or 1 for binary)
    passed INTEGER,                             -- Binary: did it pass this grader? (1=yes, 0=no)
    comment TEXT,                               -- Grader explanation of the score
    evidence TEXT,                              -- JSON: supporting evidence (test output, comparisons, etc.)

    -- For model-based graders
    judge_input TEXT,                           -- What was sent to the judge model
    judge_response TEXT,                        -- Raw judge response

    -- Run tracking (for pass@k)
    run_number INTEGER NOT NULL DEFAULT 1,      -- Which run in a multi-run experiment

    -- Cost
    cost_usd REAL DEFAULT 0.0,

    UNIQUE(experiment_id, example_id, grader_id, run_number)
);

-- Human-vs-grader agreement tracking for calibration
CREATE TABLE IF NOT EXISTS grader_calibration (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    grader_id TEXT NOT NULL REFERENCES eval_graders(id),
    example_id TEXT NOT NULL REFERENCES eval_examples(id),
    calibrated_at TEXT NOT NULL DEFAULT (datetime('now')),

    -- The grader's judgment
    grader_score REAL NOT NULL,
    grader_passed INTEGER NOT NULL,

    -- The human's judgment
    human_score REAL NOT NULL,
    human_passed INTEGER NOT NULL,
    human_notes TEXT,                            -- Human's reasoning

    -- Agreement
    scores_agree INTEGER NOT NULL,              -- 1 if human and grader agree on pass/fail
    score_delta REAL,                           -- abs(grader_score - human_score)

    -- Context
    calibration_round TEXT                       -- e.g., "2026-Q1"
);

-- Cross-agent evaluation: how one agent's output fares when consumed by another
CREATE TABLE IF NOT EXISTS cross_agent_evals (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),

    -- Producer
    producer_agent TEXT NOT NULL,
    producer_output_ref TEXT,                   -- Reference to the producing session/output

    -- Consumer
    consumer_agent TEXT NOT NULL,
    consumer_session_ref TEXT,                  -- Reference to the consuming session

    -- Quality from consumer perspective
    output_useful INTEGER,                      -- 1=useful, 0=not useful, null=not assessed
    quality_score REAL CHECK (quality_score BETWEEN 0 AND 1),
    information_loss TEXT,                       -- What information was lost or misinterpreted
    notes TEXT,

    -- Linked beads issue
    beads_issue_id TEXT
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_eval_datasets_agent ON eval_datasets(agent_name);
CREATE INDEX IF NOT EXISTS idx_eval_examples_dataset ON eval_examples(dataset_id);
CREATE INDEX IF NOT EXISTS idx_eval_examples_category ON eval_examples(category);
CREATE INDEX IF NOT EXISTS idx_eval_graders_agent ON eval_graders(agent_name);
CREATE INDEX IF NOT EXISTS idx_eval_graders_type ON eval_graders(grader_type);
CREATE INDEX IF NOT EXISTS idx_eval_experiments_agent ON eval_experiments(agent_name);
CREATE INDEX IF NOT EXISTS idx_eval_experiments_dataset ON eval_experiments(dataset_id);
CREATE INDEX IF NOT EXISTS idx_eval_results_experiment ON eval_results(experiment_id);
CREATE INDEX IF NOT EXISTS idx_eval_results_example ON eval_results(example_id);
CREATE INDEX IF NOT EXISTS idx_eval_results_grader ON eval_results(grader_id);
CREATE INDEX IF NOT EXISTS idx_grader_calibration_grader ON grader_calibration(grader_id);
CREATE INDEX IF NOT EXISTS idx_cross_agent_producer ON cross_agent_evals(producer_agent);
CREATE INDEX IF NOT EXISTS idx_cross_agent_consumer ON cross_agent_evals(consumer_agent);

-- View: aggregated quality scores per agent per grader
CREATE VIEW IF NOT EXISTS agent_quality_summary AS
SELECT
    g.agent_name,
    g.id AS grader_id,
    g.grader_type,
    g.description AS grader_description,
    COUNT(r.id) AS total_evals,
    SUM(r.passed) AS total_passed,
    ROUND(AVG(r.score), 3) AS avg_score,
    ROUND(CAST(SUM(r.passed) AS REAL) / COUNT(r.id), 3) AS pass_rate,
    MAX(r.created_at) AS last_eval_at
FROM eval_graders g
LEFT JOIN eval_results r ON r.grader_id = g.id
WHERE g.status = 'active'
GROUP BY g.agent_name, g.id
ORDER BY g.agent_name, g.grader_type;

-- View: grader calibration agreement rates
CREATE VIEW IF NOT EXISTS grader_calibration_summary AS
SELECT
    g.id AS grader_id,
    g.agent_name,
    g.description AS grader_description,
    c.calibration_round,
    COUNT(c.id) AS calibration_count,
    SUM(c.scores_agree) AS agreements,
    ROUND(CAST(SUM(c.scores_agree) AS REAL) / COUNT(c.id), 3) AS agreement_rate,
    ROUND(AVG(c.score_delta), 3) AS avg_score_delta
FROM eval_graders g
JOIN grader_calibration c ON c.grader_id = g.id
GROUP BY g.id, c.calibration_round
ORDER BY c.calibration_round DESC, g.agent_name;

-- View: quality metrics per beads issue (connects eval results to issue tracking)
CREATE VIEW IF NOT EXISTS issue_quality AS
SELECT
    e.beads_issue_id,
    e.agent_name,
    e.id AS experiment_id,
    e.pass_rate,
    e.pass_at_k_rate,
    e.pass_pow_k_rate,
    e.created_at AS experiment_date,
    COUNT(r.id) AS grader_results,
    ROUND(AVG(r.score), 3) AS avg_grader_score
FROM eval_experiments e
LEFT JOIN eval_results r ON r.experiment_id = e.id
WHERE e.beads_issue_id IS NOT NULL
GROUP BY e.beads_issue_id, e.id
ORDER BY e.created_at DESC;

-- View: MAP-Elites self-assessed fitness vs external eval scores
-- Connects workflow executions to eval experiments for the same outputs
CREATE VIEW IF NOT EXISTS fitness_calibration AS
SELECT
    ex.id AS execution_id,
    ex.executed_at,
    ex.score_composite AS self_assessed_fitness,
    ex.score_coherence AS self_coherence,
    ex.score_grounding AS self_grounding,
    ex.score_compression AS self_compression,
    ex.score_surprise AS self_surprise,
    ex.score_actionability AS self_actionability,
    exp.pass_rate AS external_pass_rate,
    ROUND(AVG(r.score), 3) AS external_avg_score,
    ROUND(ex.score_composite - AVG(r.score), 3) AS calibration_delta
FROM executions ex
JOIN eval_experiments exp ON exp.beads_issue_id = ex.beads_issue_id
LEFT JOIN eval_results r ON r.experiment_id = exp.id
WHERE ex.beads_issue_id IS NOT NULL
  AND ex.score_composite IS NOT NULL
GROUP BY ex.id
ORDER BY ABS(ex.score_composite - AVG(r.score)) DESC;
