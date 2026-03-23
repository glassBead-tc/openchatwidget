-- Seed Evaluation Data for the Agentic Dev Team
-- Phase 2: Datasets, Examples, and Code Grader Registration
--
-- Usage: sqlite3 research-workflows/workflows.db < research-workflows/seed-eval-data.sql
--
-- This populates eval_datasets, eval_examples, and eval_graders with the initial
-- seed data defined in specs/evaluation-system-spec.md.
--
-- Examples are synthetic but representative of real production scenarios based on
-- agent specifications and past session patterns.

-- ============================================================================
-- DATASETS (one per agent, version 1)
-- ============================================================================

INSERT OR IGNORE INTO eval_datasets (id, agent_name, name, description, version, example_count)
VALUES
  ('dataset-triage-fix-v1', 'triage-fix', 'Triage-Fix Seed Dataset v1',
   'Initial seed: 4 internal bugs, 3 external deps (should escalate), 3 environment issues',
   1, 10),

  ('dataset-research-taste-v1', 'research-taste', 'Research-Taste Seed Dataset v1',
   'Initial seed: mixed verdicts (proceed/simplify/defer/kill) covering meta-pruning and landscape assessment',
   1, 15),

  ('dataset-dependency-verifier-v1', 'dependency-verifier', 'Dependency-Verifier Seed Dataset v1',
   'Initial seed: 4 TRUE, 4 FALSE, 2 OUTDATED, 2 UNVERIFIABLE claims',
   1, 12),

  ('dataset-coordination-momentum-v1', 'coordination-momentum', 'Coordination-Momentum Seed Dataset v1',
   'Initial seed: 3 clean, 3 dependency chains, 2 conflicts, 2 fully-blocked states',
   1, 10),

  ('dataset-verification-judge-v1', 'verification-judge', 'Verification-Judge Seed Dataset v1',
   'Initial seed: 4 correct (VERIFY), 4 buggy (REJECT), 2 ambiguous (ESCALATE), 2 style-only',
   1, 12);


-- ============================================================================
-- EXAMPLES: triage-fix (10 examples)
-- ============================================================================

-- Category: internal-bug (4 examples)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-001', 'dataset-triage-fix-v1',
  json('{"failure_description": "Test test_workflow_step_ordering fails with AssertionError: step_order values [1,3,4] not sequential after deletion of step 2", "file": "research-workflows/test_workflows.py", "error_type": "AssertionError", "test_output": "Expected [1,2,3] but got [1,3,4]", "environment": "python 3.12, sqlite3"}'),
  json('{"root_cause": "Step deletion does not re-number remaining steps. Gap in step_order after DELETE.", "classification": "internal-bug", "fix": "Add trigger or post-delete UPDATE to re-sequence step_order values", "scope_files": ["research-workflows/schema.sql"], "should_escalate": false}'),
  'synthetic-from-spec', 'easy', 'internal-bug', 'sqlite,off-by-one,sequential');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-002', 'dataset-triage-fix-v1',
  json('{"failure_description": "eval-subagent-stop.sh exits with code 1 when jq is not installed. No eval results logged.", "file": ".claude/hooks/eval-subagent-stop.sh", "error_type": "command not found: jq", "test_output": "bash: jq: command not found", "environment": "macOS, fresh install without homebrew"}'),
  json('{"root_cause": "Hook script depends on jq but does not check for its availability. set -euo pipefail causes immediate exit on jq failure.", "classification": "internal-bug", "fix": "Add jq availability check at script start, fall back to grep-based JSON parsing or exit 0 gracefully", "scope_files": [".claude/hooks/eval-subagent-stop.sh"], "should_escalate": false}'),
  'synthetic-from-spec', 'easy', 'internal-bug', 'hooks,dependency,bash');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-003', 'dataset-triage-fix-v1',
  json('{"failure_description": "fitness_calibration view returns 0 rows even though both executions and eval_experiments tables have data with matching beads_issue_id values", "file": "research-workflows/evaluation-schema.sql", "error_type": "empty result set", "test_output": "SELECT count(*) FROM fitness_calibration; -> 0", "environment": "sqlite 3.43"}'),
  json('{"root_cause": "JOIN condition uses exp.beads_issue_id = ex.beads_issue_id but one table stores the full ID (beads-xxx) while the other stores just the short form (xxx). String mismatch prevents join.", "classification": "internal-bug", "fix": "Normalize beads_issue_id format or use LIKE/INSTR for flexible matching in the view", "scope_files": ["research-workflows/evaluation-schema.sql"], "should_escalate": false}'),
  'synthetic-from-spec', 'medium', 'internal-bug', 'sql,join,view');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-004', 'dataset-triage-fix-v1',
  json('{"failure_description": "bd create --priority=high fails with error: priority must be 0-4 or P0-P4. Multiple agent sessions have been creating issues with word priorities.", "file": ".claude/agents/coordination-momentum.md", "error_type": "validation error", "test_output": "Error: Invalid priority value high. Use 0-4 or P0-P4.", "environment": "beads CLI v0.3"}'),
  json('{"root_cause": "Agent instructions reference priority as words (high/medium/low) in some places, but bd CLI only accepts numeric 0-4 or P0-P4 format.", "classification": "internal-bug", "fix": "Update agent instructions to consistently use numeric priority format. Grep for word-based priorities across all .md files.", "scope_files": [".claude/agents/coordination-momentum.md", "CLAUDE.md"], "should_escalate": false}'),
  'synthetic-from-spec', 'easy', 'internal-bug', 'beads,priority,docs');

-- Category: external-dependency (3 examples — should escalate)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-005', 'dataset-triage-fix-v1',
  json('{"failure_description": "Exa MCP web_search_exa tool returns 403 Forbidden on all queries. Research-taste agent cannot run landscape assessment.", "file": ".mcp.json", "error_type": "HTTP 403", "test_output": "Error: 403 Forbidden - API key rate limit exceeded or expired", "environment": "Exa API v2, MCP server exa-mcp-server"}'),
  json('{"root_cause": "External dependency failure: Exa API key expired or rate-limited. This is not a code issue.", "classification": "external-dependency", "fix": "ESCALATE: Do not attempt to fix. API key management is outside agent scope.", "scope_files": [], "should_escalate": true, "escalation": {"situation": "Exa API returning 403 on all queries", "impact": "Research-taste and dependency-verifier agents cannot perform web searches", "options": [{"label": "Rotate API key", "tradeoff": "Requires human to regenerate key in Exa dashboard"}, {"label": "Fallback to WebSearch", "tradeoff": "Reduced search quality but unblocks agents"}]}}'),
  'synthetic-from-spec', 'medium', 'external-dependency', 'api,escalation,exa');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-006', 'dataset-triage-fix-v1',
  json('{"failure_description": "GitHub MCP create_pull_request fails with 422 Unprocessable Entity. PR body exceeds GitHub API max length.", "file": ".mcp.json", "error_type": "HTTP 422", "test_output": "Validation Failed: body is too long (maximum is 65536 characters)", "environment": "GitHub API v3, MCP github server"}'),
  json('{"root_cause": "External dependency constraint: GitHub API enforces 65536 char limit on PR body. Agent-generated PR descriptions can exceed this.", "classification": "external-dependency", "fix": "ESCALATE: GitHub API limit is external. Agent should truncate PR body before submission.", "scope_files": [], "should_escalate": true, "escalation": {"situation": "PR creation fails when body exceeds 64KB", "impact": "Cannot create PRs for large change sets", "options": [{"label": "Truncate body with summary", "tradeoff": "Loses detail but unblocks workflow"}, {"label": "Split into multiple PRs", "tradeoff": "More complex but preserves all information"}]}}'),
  'synthetic-from-spec', 'medium', 'external-dependency', 'github,api,escalation');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-007', 'dataset-triage-fix-v1',
  json('{"failure_description": "sqlite3 command hangs indefinitely when running eval-schema.sql against workflows.db. Database appears locked.", "file": "research-workflows/workflows.db", "error_type": "database locked", "test_output": "Error: database is locked", "environment": "sqlite 3.43, macOS, beads daemon running"}'),
  json('{"root_cause": "External dependency conflict: beads daemon holds a write lock on workflows.db for auto-sync. sqlite3 CLI cannot acquire lock.", "classification": "external-dependency", "fix": "ESCALATE: Database locking conflict between beads daemon and direct sqlite3 access.", "scope_files": [], "should_escalate": true, "escalation": {"situation": "workflows.db locked by beads daemon", "impact": "Cannot run schema migrations or manual queries", "options": [{"label": "Pause beads daemon during migrations", "tradeoff": "Temporary loss of auto-sync"}, {"label": "Use WAL mode for concurrent access", "tradeoff": "Requires schema change, may affect daemon behavior"}]}}'),
  'synthetic-from-spec', 'hard', 'external-dependency', 'sqlite,locking,beads,escalation');

-- Category: environment (3 examples)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-008', 'dataset-triage-fix-v1',
  json('{"failure_description": "eval-triage-fix.sh fails with bc: command not found. Grader score calculations return empty strings.", "file": ".claude/hooks/eval-triage-fix.sh", "error_type": "command not found: bc", "test_output": "line 28: bc: command not found", "environment": "minimal Docker container, Alpine Linux"}'),
  json('{"root_cause": "Environment issue: bc (calculator) not available in minimal containers. Hook scripts assume bc is installed.", "classification": "environment", "fix": "Replace bc calculations with awk or pure bash arithmetic. $(( )) for integers, awk for floats.", "scope_files": [".claude/hooks/eval-triage-fix.sh", ".claude/hooks/eval-research-taste.sh", ".claude/hooks/eval-dependency-verifier.sh", ".claude/hooks/eval-coordination-momentum.sh", ".claude/hooks/eval-verification-judge.sh"], "should_escalate": false}'),
  'synthetic-from-spec', 'easy', 'environment', 'bash,portability,docker');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-009', 'dataset-triage-fix-v1',
  json('{"failure_description": "07_inject_bd_context.py hook fails with ModuleNotFoundError: No module named subprocess. Python version too old.", "file": ".claude/hooks/07_inject_bd_context.py", "error_type": "ModuleNotFoundError", "test_output": "Traceback: ModuleNotFoundError: No module named subprocess", "environment": "Python 2.7, legacy system"}'),
  json('{"root_cause": "Environment issue: System python is 2.7 but hooks assume Python 3. subprocess module exists in Python 2 but import behavior differs.", "classification": "environment", "fix": "Add shebang #!/usr/bin/env python3 to all Python hook scripts. Add Python version check at script start.", "scope_files": [".claude/hooks/07_inject_bd_context.py", ".claude/hooks/01_protect_writes.py", ".claude/hooks/02_bash_policy.py", ".claude/hooks/04_mark_dirty.py"], "should_escalate": false}'),
  'synthetic-from-spec', 'easy', 'environment', 'python,version,shebang');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-triage-010', 'dataset-triage-fix-v1',
  json('{"failure_description": "git push fails with Permission denied (publickey). Agent cannot complete session landing protocol.", "file": "CLAUDE.md", "error_type": "Permission denied", "test_output": "git@github.com: Permission denied (publickey). fatal: Could not read from remote repository.", "environment": "fresh CI environment, no SSH keys configured"}'),
  json('{"root_cause": "Environment issue: SSH key not configured for git push in this environment. Not a code bug.", "classification": "environment", "fix": "Configure SSH key or switch to HTTPS with token auth. Update git remote URL if needed.", "scope_files": [], "should_escalate": false}'),
  'synthetic-from-spec', 'easy', 'environment', 'git,ssh,ci');


-- ============================================================================
-- EXAMPLES: research-taste (15 examples)
-- ============================================================================

-- Verdict: proceed (4 examples)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-001', 'dataset-research-taste-v1',
  json('{"proposal": "Investigate using MAP-Elites behavioral dimensions to automatically discover new research workflow archetypes from execution logs", "context": "Current workflow library has 10 seed workflows across 5 archetypes. Execution data accumulating in workflows.db.", "stakes": "medium"}'),
  json('{"verdict": "proceed", "compression": "We believe execution log clustering can surface new archetypes because behavioral dimensions already encode meaningful variation, and if right, the library grows organically.", "rationale": "Data exists, infrastructure exists, and the approach has clear signal: either clusters emerge or they do not. Low cost to attempt.", "landscape": "MAP-Elites in QD literature is well-established; applying it to workflow discovery is novel but grounded.", "time_to_signal": "1 session to cluster existing executions and inspect results"}'),
  'synthetic-from-spec', 'medium', 'proceed', 'map-elites,workflows,clustering');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-002', 'dataset-research-taste-v1',
  json('{"proposal": "Add cross-agent evaluation tracking to measure how research-taste verdicts correlate with downstream triage-fix outcomes", "context": "cross_agent_evals table exists but is empty. Both agents run regularly.", "stakes": "medium"}'),
  json('{"verdict": "proceed", "compression": "We believe cross-agent eval surfaces integration failures because per-agent evals miss boundary effects, and if right, system reliability improves beyond individual agent quality.", "rationale": "Infrastructure already exists (cross_agent_evals table). Primary cost is instrumenting the connection, not building new infrastructure.", "landscape": "Multi-agent eval is an active research area; most systems only do per-agent eval.", "time_to_signal": "2 sessions to instrument and collect first batch of cross-agent data"}'),
  'synthetic-from-spec', 'easy', 'proceed', 'cross-agent,evaluation,integration');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-003', 'dataset-research-taste-v1',
  json('{"proposal": "Build a simple dashboard showing agent_quality_summary view data as charts over time", "context": "eval_results accumulating from online hooks. Currently only queryable via raw SQL.", "stakes": "low"}'),
  json('{"verdict": "proceed", "compression": "We believe visualizing eval trends reveals degradation patterns that raw numbers hide, and if right, we catch quality regressions earlier.", "rationale": "Low cost, high utility. Data exists, just needs presentation. A static HTML page with Chart.js would suffice.", "time_to_signal": "Half session to build minimal viable dashboard"}'),
  'synthetic-from-spec', 'easy', 'proceed', 'dashboard,visualization,low-stakes');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-004', 'dataset-research-taste-v1',
  json('{"proposal": "Implement pass@k regression testing for the triage-fix agent using the seed dataset", "context": "Spec calls for pass@3 (capability) and pass^3 (reliability). Seed dataset being created. No regression runner exists yet.", "stakes": "high"}'),
  json('{"verdict": "proceed", "compression": "We believe automated regression testing prevents prompt changes from silently degrading agent capability, and if right, we can iterate on prompts with confidence.", "rationale": "This is core infrastructure for the eval system. Without regression testing, prompt improvements are flying blind. The spec already defines the approach.", "time_to_signal": "1 session to implement runner, 1 more to validate on seed data"}'),
  'synthetic-from-spec', 'medium', 'proceed', 'regression,pass-at-k,triage-fix');

-- Verdict: simplify (4 examples)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-005', 'dataset-research-taste-v1',
  json('{"proposal": "Build a full LangSmith integration with dataset syncing, online evaluators, annotation queues, and experiment tracking", "context": "LangSmith MCP server available. Local SQLite eval system working. Solo founder.", "stakes": "high"}'),
  json('{"verdict": "simplify", "compression": "We believe LangSmith adds value but full integration exceeds solo-founder capacity, so start with dataset sync only and expand based on actual usage.", "rationale": "Full integration is 4+ sessions of work for uncertain payoff. The local SQLite system already works. Start with the highest-value piece (dataset sync for backup/versioning) and add more only if the local system proves insufficient.", "simplification": "Phase 1: Configure MCP server + manual dataset sync. Phase 2: Add online evaluators only if local hooks prove inadequate.", "time_to_signal": "1 session for MCP config, then observe usage for 2 weeks"}'),
  'synthetic-from-spec', 'medium', 'simplify', 'langsmith,integration,scope');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-006', 'dataset-research-taste-v1',
  json('{"proposal": "Implement a comprehensive CI/CD pipeline with GitHub Actions that runs all eval graders on every PR, blocks merges on failures, and posts results as PR comments", "context": "Currently manual eval only. No CI/CD exists. Solo founder repo.", "stakes": "medium"}'),
  json('{"verdict": "simplify", "compression": "We believe CI eval gates catch regressions before merge, but a full pipeline is over-engineered for a spec repo — a pre-push hook running code graders achieves 80% of the value.", "rationale": "Full CI/CD pipeline has high setup cost and maintenance burden for a spec repository that changes infrequently. A local pre-push git hook running code graders provides most of the safety with minimal infrastructure.", "simplification": "Git pre-push hook that runs code graders locally. Graduate to CI/CD only when team size > 1.", "time_to_signal": "30 minutes to set up pre-push hook"}'),
  'synthetic-from-spec', 'easy', 'simplify', 'ci-cd,over-engineering,git-hooks');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-007', 'dataset-research-taste-v1',
  json('{"proposal": "Create a web-based annotation interface for human calibration reviews with user auth, comment threads, and scoring widgets", "context": "Phase 4 calls for quarterly human calibration (25 examples). Currently no annotation interface.", "stakes": "low"}'),
  json('{"verdict": "simplify", "compression": "We believe structured annotation improves calibration quality, but 25 quarterly examples do not justify a web app — a SQLite CLI script with structured prompts suffices.", "rationale": "25 examples per quarter is a tiny volume. A simple script that displays each example and collects human scores via stdin is faster to build and use than a web interface. If volume grows past 100/quarter, reconsider.", "simplification": "Bash/Python script: display example, prompt for score, insert into grader_calibration table.", "time_to_signal": "1 hour to build annotation script"}'),
  'synthetic-from-spec', 'easy', 'simplify', 'annotation,over-engineering,calibration');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-008', 'dataset-research-taste-v1',
  json('{"proposal": "Build an agent-to-agent communication protocol using a message queue (Redis/RabbitMQ) so agents can share findings in real-time", "context": "Agents currently communicate through beads issues and git-persisted files. Solo founder, no server infrastructure.", "stakes": "high"}'),
  json('{"verdict": "simplify", "compression": "We believe inter-agent communication improves coordination, but adding message queue infrastructure to a spec repo contradicts the solo-founder constraint — beads + git already provide async communication.", "rationale": "Real-time communication solves a problem that does not yet exist in a solo-founder context. Agents run sequentially or in limited parallelism. Beads issues and shared files are sufficient for current scale.", "simplification": "Document cross-agent data contracts in CLAUDE.md. Use existing beads dependency system for sequencing.", "time_to_signal": "Already observable — current system handles coordination adequately"}'),
  'synthetic-from-spec', 'medium', 'simplify', 'message-queue,over-engineering,infra');

-- Verdict: defer (4 examples)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-009', 'dataset-research-taste-v1',
  json('{"proposal": "Research how to fine-tune a small model on agent transcripts to create a specialized evaluation judge", "context": "Current eval uses code graders + Haiku-as-judge. No fine-tuning infrastructure.", "stakes": "high"}'),
  json('{"verdict": "defer", "compression": "We believe fine-tuned judges could outperform prompted Haiku, but we lack the training data volume and infrastructure to validate this — defer until 500+ graded examples exist.", "rationale": "Fine-tuning requires: (1) substantial training data (current: 0 eval results), (2) compute infrastructure, (3) evaluation of the fine-tuned model itself. All three prerequisites are missing. This is premature.", "time_to_signal": "Cannot estimate — prerequisites not met", "resurrection_condition": "When eval_results has 500+ entries with human-calibrated ground truth"}'),
  'synthetic-from-spec', 'medium', 'defer', 'fine-tuning,premature,prerequisites');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-010', 'dataset-research-taste-v1',
  json('{"proposal": "Investigate using reinforcement learning from human feedback (RLHF) to improve agent prompts automatically", "context": "Evaluation system being built. No RLHF infrastructure. Solo founder.", "stakes": "high"}'),
  json('{"verdict": "defer", "compression": "We believe RLHF could automate prompt improvement, but the feedback loop (eval → prompt change → regression test) is not yet operational — defer until the manual loop works.", "rationale": "RLHF requires a working feedback loop to optimize. The manual version (human reviews evals, updates prompts, runs regression) does not yet exist. Build the manual loop first, then automate it.", "time_to_signal": "Cannot estimate — manual loop not yet operational", "resurrection_condition": "When 3+ manual prompt improvement cycles have been completed successfully"}'),
  'synthetic-from-spec', 'medium', 'defer', 'rlhf,premature,feedback-loop');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-011', 'dataset-research-taste-v1',
  json('{"proposal": "Add multi-language support to the research workflow system — allow workflows to be written in different natural languages", "context": "All current workflows and agents operate in English. No international users.", "stakes": "low"}'),
  json('{"verdict": "defer", "compression": "We believe multi-language support would broaden reach, but with zero international users and no localization infrastructure, this solves a non-existent problem.", "rationale": "No demand signal exists. Adding i18n to a spec repo used by one person is pure speculation about future needs. If international collaboration begins, revisit.", "time_to_signal": "N/A — no demand signal", "resurrection_condition": "When a non-English-speaking collaborator joins the project"}'),
  'synthetic-from-spec', 'easy', 'defer', 'i18n,no-demand,premature');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-012', 'dataset-research-taste-v1',
  json('{"proposal": "Build a cost tracking system that monitors API spend across all agent sessions and alerts when approaching budget limits", "context": "Agents use Claude API, Exa API, Firecrawl API. No cost tracking beyond manual checks. Budget exists but is informal.", "stakes": "medium"}'),
  json('{"verdict": "defer", "compression": "We believe cost tracking prevents budget overruns, but current spend is well within limits and manual checks suffice — defer until monthly spend exceeds $50 or a surprise bill occurs.", "rationale": "Building cost tracking infrastructure when costs are low and predictable is premature optimization. The trigger for this work is a cost surprise, not a theoretical concern.", "time_to_signal": "N/A — trigger-based", "resurrection_condition": "When monthly API spend exceeds $50 or an unexpected charge occurs"}'),
  'synthetic-from-spec', 'easy', 'defer', 'cost-tracking,premature,trigger-based');

-- Verdict: kill (3 examples)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-013', 'dataset-research-taste-v1',
  json('{"proposal": "Replace SQLite with PostgreSQL for the evaluation system to enable concurrent access and better query performance", "context": "workflows.db is ~50KB. Single user. Beads daemon is the only concurrent accessor.", "stakes": "high"}'),
  json('{"verdict": "kill", "compression": "We believe PostgreSQL solves concurrent access, but the actual problem is a single locking conflict solvable with WAL mode — replacing the entire database is solving the wrong problem.", "rationale": "PostgreSQL adds operational complexity (server process, connection management, migrations, backups) for a problem that does not exist at current scale. SQLite with WAL mode handles modest concurrency. This is resume-driven development.", "time_to_signal": "N/A — wrong framing"}'),
  'synthetic-from-spec', 'easy', 'kill', 'postgresql,over-engineering,wrong-problem');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-014', 'dataset-research-taste-v1',
  json('{"proposal": "Build a microservices architecture where each agent runs as an independent service communicating via gRPC", "context": "Agents are Claude Code subagents defined by .md files. No server infrastructure. Solo founder.", "stakes": "high"}'),
  json('{"verdict": "kill", "compression": "We believe microservices add no value because agents are prompt-defined subprocesses, not independently deployable services — this fundamentally misunderstands the architecture.", "rationale": "Claude Code agents are not long-running processes. They are subagent invocations defined by markdown files. Converting them to microservices would require building infrastructure that contradicts the entire design philosophy (git-native, SQLite, no new infra).", "time_to_signal": "N/A — architectural mismatch"}'),
  'synthetic-from-spec', 'easy', 'kill', 'microservices,architecture-mismatch');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-taste-015', 'dataset-research-taste-v1',
  json('{"proposal": "Train a custom embedding model on our codebase to improve semantic search accuracy for the research workflows", "context": "Codebase is ~50 files. Exa provides web search. No internal semantic search need identified.", "stakes": "medium"}'),
  json('{"verdict": "kill", "compression": "We believe custom embeddings solve nothing because the codebase is small enough for grep and the proposal lacks a concrete use case — solution seeking a problem.", "rationale": "50 files is trivially searchable with grep/glob. No user or agent has reported search quality issues. Training a custom model requires data, compute, and ongoing maintenance for zero identified benefit.", "time_to_signal": "N/A — no problem to solve"}'),
  'synthetic-from-spec', 'easy', 'kill', 'embeddings,no-problem,solution-seeking');


-- ============================================================================
-- EXAMPLES: dependency-verifier (12 examples)
-- ============================================================================

-- Category: TRUE claims (4 — should verify as VERIFIED)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-001', 'dataset-dependency-verifier-v1',
  json('{"claim": "Claude Code SubagentStop hook receives agent_transcript_path in the event payload", "criticality": "HIGH", "source": "Claude Code documentation", "context": "Used by eval-subagent-stop.sh to read agent output for grading"}'),
  json('{"result": "VERIFIED", "confidence": 0.95, "evidence": "Tested in production: SubagentStop hook receives JSON with agent_transcript_path pointing to valid .jsonl file. Confirmed across 5+ agent sessions.", "test_method": "Ran triage-fix subagent, inspected hook stdin JSON payload"}'),
  'synthetic-from-spec', 'easy', 'true-claim', 'claude-code,hooks,api');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-002', 'dataset-dependency-verifier-v1',
  json('{"claim": "SQLite CREATE TABLE IF NOT EXISTS is safe to run multiple times — it will not error or modify existing data", "criticality": "MEDIUM", "source": "SQLite documentation", "context": "evaluation-schema.sql uses IF NOT EXISTS for all table creation"}'),
  json('{"result": "VERIFIED", "confidence": 0.99, "evidence": "SQLite docs confirm: IF NOT EXISTS causes no-op when table already exists. Tested: ran schema.sql 3 times against same DB, no errors, existing data preserved.", "test_method": "Ran CREATE TABLE IF NOT EXISTS against populated DB, verified row counts unchanged"}'),
  'synthetic-from-spec', 'easy', 'true-claim', 'sqlite,schema,idempotent');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-003', 'dataset-dependency-verifier-v1',
  json('{"claim": "The gh CLI can create pull requests with multiline body text using heredoc syntax", "criticality": "MEDIUM", "source": "GitHub CLI documentation", "context": "Used in session completion protocol for creating PRs"}'),
  json('{"result": "VERIFIED", "confidence": 0.90, "evidence": "Tested: gh pr create --title test --body \"$(cat <<EOF\\nmultiline\\nbody\\nEOF\\n)\" successfully creates PR with preserved line breaks. gh version 2.40+.", "test_method": "Created test PR with multiline heredoc body, inspected rendered markdown"}'),
  'synthetic-from-spec', 'easy', 'true-claim', 'github-cli,heredoc,pr');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-004', 'dataset-dependency-verifier-v1',
  json('{"claim": "jq -r .field on JSON input returns the raw string value without quotes", "criticality": "LOW", "source": "jq manual", "context": "eval-subagent-stop.sh uses jq -r to extract agent_type from hook input"}'),
  json('{"result": "VERIFIED", "confidence": 0.99, "evidence": "jq manual confirms -r flag outputs raw strings. Tested: echo {\"a\":\"hello\"} | jq -r .a outputs hello without quotes.", "test_method": "Ran jq -r against sample JSON, compared with/without -r flag"}'),
  'synthetic-from-spec', 'easy', 'true-claim', 'jq,cli,parsing');

-- Category: FALSE claims (4 — should verify as FAILED)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-005', 'dataset-dependency-verifier-v1',
  json('{"claim": "Claude Code hooks can modify the agent prompt by returning modified_prompt in hookSpecificOutput", "criticality": "HIGH", "source": "Blog post about Claude Code extensibility", "context": "Proposed approach for injecting eval context into agent sessions"}'),
  json('{"result": "FAILED", "confidence": 0.85, "evidence": "Claude Code hooks documentation shows hookSpecificOutput supports additionalContext (appended to context) but NOT modified_prompt. There is no mechanism to rewrite the agent prompt from a hook.", "test_method": "Reviewed Claude Code hook documentation, tested returning modified_prompt — field ignored", "escalation": {"situation": "Cannot modify agent prompts via hooks", "impact": "Alternative approach needed for injecting eval context", "options": [{"label": "Use additionalContext instead", "tradeoff": "Appended, not injected — less control but functional"}, {"label": "Modify agent .md files directly", "tradeoff": "Permanent change, not session-specific"}]}}'),
  'synthetic-from-spec', 'medium', 'false-claim', 'claude-code,hooks,api-mismatch');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-006', 'dataset-dependency-verifier-v1',
  json('{"claim": "SQLite supports concurrent write transactions from multiple processes using WAL mode", "criticality": "HIGH", "source": "SQLite WAL documentation", "context": "Proposed solution for beads daemon locking conflict with direct sqlite3 access"}'),
  json('{"result": "FAILED", "confidence": 0.80, "evidence": "SQLite WAL mode allows concurrent reads during writes, but still only ONE writer at a time. Multiple concurrent writers will still get SQLITE_BUSY. WAL does not solve the concurrent write problem.", "test_method": "Opened two sqlite3 sessions in WAL mode, attempted concurrent INSERTs — second process got SQLITE_BUSY after timeout", "escalation": {"situation": "WAL mode does not enable concurrent writes", "impact": "beads daemon and eval hooks cannot both write simultaneously", "options": [{"label": "Serialize writes with flock", "tradeoff": "Adds lock file management but prevents SQLITE_BUSY"}, {"label": "Increase busy_timeout", "tradeoff": "Retries automatically, may add latency"}]}}'),
  'synthetic-from-spec', 'hard', 'false-claim', 'sqlite,wal,concurrency');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-007', 'dataset-dependency-verifier-v1',
  json('{"claim": "Exa web_search_exa returns results with full page content by default", "criticality": "MEDIUM", "source": "Exa API documentation", "context": "Research-taste agent relies on search results containing page content for landscape assessment"}'),
  json('{"result": "FAILED", "confidence": 0.90, "evidence": "Exa search returns titles, URLs, and snippets by default. Full page content requires the contents parameter set to text or highlights. Without this parameter, only metadata is returned.", "test_method": "Called web_search_exa without contents parameter, inspected response — no full text"}'),
  'synthetic-from-spec', 'medium', 'false-claim', 'exa,api,default-behavior');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-008', 'dataset-dependency-verifier-v1',
  json('{"claim": "The beads CLI bd create command supports --labels flag for adding labels to issues", "criticality": "LOW", "source": "Assumed from GitHub Issues analogy", "context": "Coordination-momentum agent tries to label issues by type"}'),
  json('{"result": "FAILED", "confidence": 0.95, "evidence": "bd create --help shows no --labels flag. Beads uses --type for issue classification (task/bug/feature) and --tags for free-form tagging, not --labels.", "test_method": "Ran bd create --labels=test, got error: unknown flag --labels. Confirmed via bd create --help"}'),
  'synthetic-from-spec', 'easy', 'false-claim', 'beads,cli,api-mismatch');

-- Category: OUTDATED claims (2 — spec says one thing, implementation does another)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-009', 'dataset-dependency-verifier-v1',
  json('{"claim": "Claude Haiku 3.5 model ID is claude-3-5-haiku-20241022", "criticality": "HIGH", "source": "Anthropic model documentation (2024)", "context": "eval spec references Haiku as judge model for LLM graders"}'),
  json('{"result": "PARTIAL", "confidence": 0.70, "evidence": "The claude-3-5-haiku-20241022 ID still works but Anthropic released Claude 4.5 Haiku with ID claude-haiku-4-5-20251001 which is the current recommended model. The old ID is deprecated but functional.", "test_method": "Checked Anthropic API docs, tested both model IDs — both respond but 4.5 is current"}'),
  'synthetic-from-spec', 'medium', 'outdated-claim', 'anthropic,model-id,versioning');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-010', 'dataset-dependency-verifier-v1',
  json('{"claim": "LangSmith evaluate() function accepts a target parameter for the function to evaluate", "criticality": "MEDIUM", "source": "LangSmith docs (early 2025)", "context": "Planned regression testing integration with LangSmith"}'),
  json('{"result": "PARTIAL", "confidence": 0.75, "evidence": "LangSmith SDK evolved: early versions used target parameter, current version uses different parameter naming. The evaluate() API signature changed between SDK versions. Check current SDK version for exact parameter names.", "test_method": "Compared cached LangSmith docs against current PyPI package API reference"}'),
  'synthetic-from-spec', 'hard', 'outdated-claim', 'langsmith,sdk,api-evolution');

-- Category: UNVERIFIABLE claims (2)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-011', 'dataset-dependency-verifier-v1',
  json('{"claim": "The Exa API processes over 1 million queries per day with 99.9% uptime", "criticality": "LOW", "source": "Exa marketing page", "context": "Evaluating Exa reliability for research-taste agent dependency"}'),
  json('{"result": "UNTESTABLE", "confidence": 0.20, "evidence": "Marketing claims about internal metrics cannot be independently verified. No public status page with historical uptime data found. Our own usage is too low-volume to infer system-level reliability.", "test_method": "Searched for Exa status page, SLA documentation, and third-party monitoring — none found"}'),
  'synthetic-from-spec', 'medium', 'unverifiable', 'exa,marketing,reliability');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-verifier-012', 'dataset-dependency-verifier-v1',
  json('{"claim": "Using Claude Haiku as an eval judge produces results that agree with human judgment 85% of the time for code quality assessment", "criticality": "HIGH", "source": "Anthropic blog post on model-based evaluation", "context": "eval spec assumes Haiku-as-judge is reliable enough for online eval"}'),
  json('{"result": "UNTESTABLE", "confidence": 0.30, "evidence": "The 85% figure is from Anthropic internal benchmarks on their specific eval tasks. Agreement rate depends heavily on the specific domain, rubric, and task type. Cannot verify without running our own calibration study.", "test_method": "No independent replication possible without running grader_calibration with our specific judge prompts and examples"}'),
  'synthetic-from-spec', 'hard', 'unverifiable', 'haiku,judge,calibration');


-- ============================================================================
-- EXAMPLES: coordination-momentum (10 examples)
-- ============================================================================

-- Category: clean (3 — few issues, no blockers)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-001', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "○ issue-001 [P2] [task] - Write unit tests\n○ issue-002 [P3] [task] - Update docs\n✓ issue-003 [P1] [task] - Fix schema (CLOSED)", "bd_blocked_output": "(none)", "bd_stats_output": "open: 2, closed: 1, blocked: 0", "git_log": "abc1234 fix: schema migration (2h ago)\ndef5678 feat: add eval tables (5h ago)", "active_agents": []}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_available": ["issue-001", "issue-002"], "expected_blocked": [], "expected_conflicts": [], "expected_recommendation": "Pick up issue-001 (higher priority)", "boundary_check": "no_reprioritization"}'),
  'synthetic-from-spec', 'easy', 'clean', 'simple,no-blockers');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-002', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "● issue-010 [P1] [task] - Implement graders (in_progress)\n○ issue-011 [P2] [task] - Add seed data\n○ issue-012 [P3] [task] - Write docs", "bd_blocked_output": "(none)", "bd_stats_output": "open: 3, in_progress: 1, closed: 5, blocked: 0", "git_log": "aaa1111 feat: grader scaffold (30m ago)", "active_agents": ["triage-fix on issue-010"]}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_active": [{"issue": "issue-010", "agent": "triage-fix", "recent_activity": true}], "expected_available": ["issue-011", "issue-012"], "expected_recommendation": "issue-010 in progress with recent commits, pick up issue-011 next"}'),
  'synthetic-from-spec', 'easy', 'clean', 'in-progress,recent-activity');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-003', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "✓ issue-020 [P1] - Schema done (CLOSED)\n✓ issue-021 [P1] - Spec done (CLOSED)\n✓ issue-022 [P2] - Hooks done (CLOSED)", "bd_blocked_output": "(none)", "bd_stats_output": "open: 0, closed: 3, blocked: 0", "git_log": "recent commits showing all work completed", "active_agents": []}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_active": [], "expected_available": [], "expected_recommendation": "All tracked work complete. Consider creating new issues or checking for untracked work."}'),
  'synthetic-from-spec', 'easy', 'clean', 'all-complete,empty-queue');

-- Category: dependency-chain (3 — issues blocking other issues)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-004', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "○ issue-030 [P2] [task] - Seed data (blocked by issue-029)\n○ issue-031 [P2] [task] - Code graders (blocked by issue-029)\n● issue-029 [P1] [task] - Write schema (in_progress)\n○ issue-032 [P3] [task] - LLM judges (blocked by issue-031)", "bd_blocked_output": "issue-030 blocked by issue-029\nissue-031 blocked by issue-029\nissue-032 blocked by issue-031", "bd_stats_output": "open: 4, in_progress: 1, blocked: 3", "git_log": "bbb2222 wip: schema draft (1h ago)", "active_agents": []}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_active": [{"issue": "issue-029", "status": "in_progress"}], "expected_blocked": ["issue-030", "issue-031", "issue-032"], "expected_dependency_chain": "issue-029 → issue-030/031 → issue-032", "expected_recommendation": "Focus on completing issue-029 to unblock 3 downstream issues. Critical path: 029 → 031 → 032."}'),
  'synthetic-from-spec', 'medium', 'dependency-chain', 'blocking,critical-path');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-005', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "○ issue-040 [P1] [task] - API design (blocked by issue-041)\n○ issue-041 [P1] [task] - Requirements review (blocked by issue-040)", "bd_blocked_output": "issue-040 blocked by issue-041\nissue-041 blocked by issue-040", "bd_stats_output": "open: 2, blocked: 2", "git_log": "no recent commits", "active_agents": []}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_blocked": ["issue-040", "issue-041"], "expected_spirals": ["dependency_deadlock"], "expected_recommendation": "ESCALATE: Circular dependency detected between issue-040 and issue-041. Human must break the cycle by removing one dependency."}'),
  'synthetic-from-spec', 'hard', 'dependency-chain', 'circular,deadlock,escalation');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-006', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "● issue-050 [P1] [task] - Phase 1 impl (in_progress)\n○ issue-051 [P2] [task] - Phase 2 impl (blocked by issue-050)\n○ issue-052 [P2] [task] - Phase 2 tests (blocked by issue-051)\n○ issue-053 [P3] [task] - Phase 3 impl (blocked by issue-052)\n○ issue-054 [P2] [task] - Docs update (no blockers)", "bd_blocked_output": "issue-051 blocked by issue-050\nissue-052 blocked by issue-051\nissue-053 blocked by issue-052", "bd_stats_output": "open: 5, in_progress: 1, blocked: 3", "git_log": "ccc3333 feat: phase 1 progress (20m ago)", "active_agents": ["triage-fix on issue-050"]}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_active": [{"issue": "issue-050", "recent_activity": true}], "expected_available": ["issue-054"], "expected_dependency_chain": "issue-050 → 051 → 052 → 053", "expected_recommendation": "issue-050 in progress with recent activity. issue-054 (docs) is available and parallelizable. Long chain: 050→051→052→053 means phase 3 is 3 steps away."}'),
  'synthetic-from-spec', 'medium', 'dependency-chain', 'long-chain,parallelizable');

-- Category: conflict (2 — parallel work touching same files)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-007', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "● issue-060 [P1] [task] - Refactor eval hooks (in_progress)\n● issue-061 [P2] [task] - Add new grader to hooks (in_progress)", "bd_blocked_output": "(none)", "bd_stats_output": "open: 2, in_progress: 2", "git_log": "ddd4444 refactor: hooks structure (10m ago, issue-060)\neee5555 feat: new grader (15m ago, issue-061)", "active_agents": ["triage-fix on issue-060", "research-taste on issue-061"], "shared_files": [".claude/hooks/eval-subagent-stop.sh"]}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_conflicts": [{"issues": ["issue-060", "issue-061"], "shared_files": [".claude/hooks/eval-subagent-stop.sh"], "risk": "merge conflict"}], "expected_recommendation": "CONFLICT: issue-060 and issue-061 both modify eval hook files. Recommend serializing: complete 060 first, then rebase 061."}'),
  'synthetic-from-spec', 'medium', 'conflict', 'merge-conflict,parallel-work');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-008', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "● issue-070 [P2] [task] - Update CLAUDE.md with new hooks (in_progress)\n● issue-071 [P2] [task] - Add evaluation section to CLAUDE.md (in_progress)", "bd_blocked_output": "(none)", "bd_stats_output": "open: 2, in_progress: 2", "git_log": "fff6666 docs: hook table update (5m ago)\nggg7777 docs: eval section draft (8m ago)", "active_agents": [], "shared_files": ["CLAUDE.md"]}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_conflicts": [{"issues": ["issue-070", "issue-071"], "shared_files": ["CLAUDE.md"], "risk": "merge conflict on same file"}], "expected_recommendation": "CONFLICT: Both issues modify CLAUDE.md. Since both are P2, suggest combining into a single issue or completing one before starting the other."}'),
  'synthetic-from-spec', 'easy', 'conflict', 'same-file,docs');

-- Category: fully-blocked (2 — all workstreams blocked)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-009', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "○ issue-080 [P1] [task] - Deploy eval system (blocked by issue-082)\n○ issue-081 [P2] [task] - Run regression (blocked by issue-080)\n○ issue-082 [P1] [bug] - Fix DB locking (blocked by external: beads daemon issue)", "bd_blocked_output": "issue-080 blocked by issue-082\nissue-081 blocked by issue-080\nissue-082 blocked by external dependency", "bd_stats_output": "open: 3, blocked: 3", "git_log": "no commits in 2 hours", "active_agents": []}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_active": [], "expected_available": [], "expected_blocked": ["issue-080", "issue-081", "issue-082"], "expected_spirals": ["starvation"], "expected_recommendation": "ESCALATE: All workstreams blocked. Root blocker is issue-082 (external dependency). No work can proceed without human intervention to resolve the beads daemon DB locking issue."}'),
  'synthetic-from-spec', 'hard', 'fully-blocked', 'all-blocked,escalation,external');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-coord-010', 'dataset-coordination-momentum-v1',
  json('{"bd_list_output": "● issue-090 [P1] [task] - Implement feature X (in_progress, stale)\n○ issue-091 [P2] [task] - Test feature X (blocked by issue-090)\n○ issue-092 [P2] [task] - Document feature X (blocked by issue-090)", "bd_blocked_output": "issue-091 blocked by issue-090\nissue-092 blocked by issue-090", "bd_stats_output": "open: 3, in_progress: 1, blocked: 2", "git_log": "last commit: 3 days ago for issue-090", "active_agents": []}'),
  json('{"expected_sections": ["active_workstreams", "blocked", "available", "conflicts", "spirals", "recommendation"], "expected_active": [{"issue": "issue-090", "stale": true}], "expected_spirals": ["starvation", "stale_work"], "expected_recommendation": "ESCALATE: issue-090 has been in_progress for 3 days with no recent commits. It blocks 2 downstream issues. Recommend: (1) check if issue-090 is actually stuck and needs help, or (2) reassign to a different approach."}'),
  'synthetic-from-spec', 'medium', 'fully-blocked', 'stale,starvation,escalation');


-- ============================================================================
-- EXAMPLES: verification-judge (12 examples)
-- ============================================================================

-- Category: correct (4 — should VERIFY)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-001', 'dataset-verification-judge-v1',
  json('{"artifact": "evaluation-schema.sql", "spec_requirements": ["7 new tables", "4 views", "indexes on common query columns", "all tables use IF NOT EXISTS", "foreign key references valid"], "implementation_summary": "SQL file with 7 CREATE TABLE, 4 CREATE VIEW, 17 CREATE INDEX statements. All use IF NOT EXISTS. FK references match table/column names."}'),
  json('{"expected_verdict": "VERIFIED", "pass1_deterministic": {"tests": "N/A (SQL schema)", "types": "N/A", "lint": "SQL syntax valid", "build": "Schema loads cleanly"}, "pass2_spec": "All 7 tables match spec, all 4 views present, indexes cover specified columns", "pass3_perspectives": {"logician": "No contradictions in constraints", "architect": "Consistent naming conventions", "security": "No injection risks in DDL", "implementer": "IF NOT EXISTS makes idempotent"}, "blocking_issues": [], "advisory_issues": []}'),
  'synthetic-from-spec', 'easy', 'correct', 'schema,clean-pass');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-002', 'dataset-verification-judge-v1',
  json('{"artifact": "eval-triage-fix.sh", "spec_requirements": ["3 graders: format_compliance, scope_compliance, escalation_judgment", "logs results to eval_results table", "returns additionalContext on failures", "exits 0 on success"], "implementation_summary": "Bash script implementing 3 graders with grep-based checks, sqlite3 inserts, and jq JSON output for failures."}'),
  json('{"expected_verdict": "VERIFIED", "pass1_deterministic": {"tests": "N/A (hook script)", "lint": "shellcheck clean", "build": "Script is executable"}, "pass2_spec": "All 3 graders present, results logged to eval_results, additionalContext returned on failure", "pass3_perspectives": {"logician": "Score calculations correct", "architect": "Follows same pattern as other eval hooks", "security": "SQL values should be parameterized (advisory)", "implementer": "bc dependency may not be available everywhere (advisory)"}, "blocking_issues": [], "advisory_issues": ["SQL injection risk from unescaped AGENT_ID in sqlite3 command", "bc dependency for float arithmetic"]}'),
  'synthetic-from-spec', 'medium', 'correct', 'hooks,advisory-only');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-003', 'dataset-verification-judge-v1',
  json('{"artifact": "CLAUDE.md update adding evaluation section", "spec_requirements": ["documents eval system overview", "references schema and spec files", "lists hook scripts with events and purposes", "follows existing CLAUDE.md structure"], "implementation_summary": "Added Evaluation System section with overview, schema reference, hook table, and views list. Follows existing heading structure."}'),
  json('{"expected_verdict": "VERIFIED", "pass1_deterministic": {"lint": "Markdown valid", "build": "N/A"}, "pass2_spec": "All required content present, file references accurate", "pass3_perspectives": {"logician": "No contradictions with existing content", "architect": "Section placement consistent with doc structure", "security": "No sensitive info exposed", "implementer": "All file paths verified to exist"}, "blocking_issues": [], "advisory_issues": []}'),
  'synthetic-from-spec', 'easy', 'correct', 'docs,clean-pass');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-004', 'dataset-verification-judge-v1',
  json('{"artifact": "seed-eval-data.sql", "spec_requirements": ["5 datasets (one per agent)", "~59 examples total", "13 code grader registrations", "realistic scenarios based on agent specs", "proper foreign key references"], "implementation_summary": "SQL file with 5 dataset inserts, 59 example inserts, and 13 grader registrations. All IDs follow naming conventions, FK references match existing tables."}'),
  json('{"expected_verdict": "VERIFIED", "pass1_deterministic": {"lint": "SQL syntax valid", "build": "Loads into workflows.db without errors"}, "pass2_spec": "5 datasets, 59 examples, 13 graders all present and correctly structured", "pass3_perspectives": {"logician": "Example categories match spec distributions", "architect": "Consistent ID naming conventions", "security": "No sensitive data in examples", "implementer": "INSERT OR IGNORE for idempotency"}, "blocking_issues": [], "advisory_issues": []}'),
  'synthetic-from-spec', 'medium', 'correct', 'seed-data,clean-pass');

-- Category: buggy (4 — should REJECT with specific issues)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-005', 'dataset-verification-judge-v1',
  json('{"artifact": "eval-coordination-momentum.sh with missing section check", "spec_requirements": ["check for 6 required sections", "check for no reprioritization", "log results to eval_results"], "implementation_summary": "Script checks for 5 sections instead of 6 (missing spiral detection check). Reprioritization check works. Results logged correctly."}'),
  json('{"expected_verdict": "REJECTED", "pass1_deterministic": {"tests": "Missing section check"}, "pass2_spec": "Requirement: 6 sections. Implementation: 5 sections. Missing: spiral detection", "blocking_issues": [{"description": "Grader checks for 5 sections but spec requires 6. Missing check for spiral detection section.", "location": "eval-coordination-momentum.sh, REQUIRED array", "fix": "Add Spiral to REQUIRED array"}], "advisory_issues": []}'),
  'synthetic-from-spec', 'easy', 'buggy', 'missing-check,incomplete');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-006', 'dataset-verification-judge-v1',
  json('{"artifact": "eval-subagent-stop.sh with SQL injection vulnerability", "spec_requirements": ["dispatch to agent-specific scripts", "log generic record if no script", "handle missing transcript gracefully"], "implementation_summary": "Script reads agent_type from JSON input and interpolates directly into SQL query without sanitization. An agent_type containing SQL metacharacters could corrupt the database."}'),
  json('{"expected_verdict": "REJECTED", "pass1_deterministic": {"security": "SQL injection in sqlite3 command"}, "pass2_spec": "Functional requirements met but with security flaw", "blocking_issues": [{"description": "AGENT_TYPE is interpolated directly into SQL string on line 50-51. If agent_type contains single quotes or SQL metacharacters, this corrupts the query or enables injection.", "location": "eval-subagent-stop.sh:50-51", "fix": "Use parameterized queries or sanitize AGENT_TYPE before interpolation"}], "advisory_issues": []}'),
  'synthetic-from-spec', 'medium', 'buggy', 'security,sql-injection');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-007', 'dataset-verification-judge-v1',
  json('{"artifact": "evaluation-schema.sql with broken view", "spec_requirements": ["fitness_calibration view joins executions with eval_experiments", "agent_quality_summary aggregates by agent and grader"], "implementation_summary": "fitness_calibration view references ex.beads_issue_id but the executions table column is named issue_id. View will return 0 rows due to column name mismatch."}'),
  json('{"expected_verdict": "REJECTED", "pass1_deterministic": {"build": "Schema loads but view returns wrong results"}, "pass2_spec": "View exists but does not function as specified", "blocking_issues": [{"description": "fitness_calibration view references ex.beads_issue_id but the executions table uses column name issue_id. JOIN produces 0 rows.", "location": "evaluation-schema.sql, fitness_calibration view definition", "fix": "Change ex.beads_issue_id to ex.issue_id in the view JOIN condition"}], "advisory_issues": []}'),
  'synthetic-from-spec', 'medium', 'buggy', 'sql,view,column-mismatch');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-008', 'dataset-verification-judge-v1',
  json('{"artifact": "agent spec with contradictory escalation rules", "spec_requirements": ["triage-fix escalates after 3 failed attempts", "triage-fix has 4 phases with turn budgets", "all phases must complete before session end"], "implementation_summary": "Phase 3 allows max 3 repair attempts. But Phase 4 says run full test suite. If all 3 attempts in Phase 3 fail, Phase 4 still runs tests on broken code, producing misleading pass/fail evidence."}'),
  json('{"expected_verdict": "REJECTED", "pass1_deterministic": {"consistency": "Contradictory phase logic"}, "pass2_spec": "Phase 3 escalation and Phase 4 evidence collection conflict", "blocking_issues": [{"description": "If all 3 repair attempts fail in Phase 3, the agent should escalate. But Phase 4 instructions say run full test suite and document results. Running tests after escalation produces misleading evidence.", "location": "triage-fix.md, Phase 3-4 transition", "fix": "Add condition: if Phase 3 escalated, Phase 4 should document the escalation, not run tests on unfixed code"}], "advisory_issues": []}'),
  'synthetic-from-spec', 'hard', 'buggy', 'spec-contradiction,logic');

-- Category: ambiguous (2 — should ESCALATE)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-009', 'dataset-verification-judge-v1',
  json('{"artifact": "coordination-momentum agent claiming issue for itself", "spec_requirements": ["report status accurately", "recommend next actions", "do not reprioritize"], "implementation_summary": "Agent output includes: Recommendation: I will now work on issue-054. This could be interpreted as the coordination agent claiming work (scope violation) or as a recommendation for which agent should pick up the work next."}'),
  json('{"expected_verdict": "ESCALATE", "reason": "Ambiguous whether coordination agent is claiming work (violates scope) or recommending what should be worked on next (within scope). The phrasing I will now work on suggests self-assignment, but the agent may be speaking on behalf of the system.", "pass2_spec": "Spec says recommend but does not explicitly forbid self-assignment language", "blocking_issues": [], "advisory_issues": [{"description": "Recommendation phrasing is ambiguous — clarify in agent spec whether coordinator can use first-person recommendations"}]}'),
  'synthetic-from-spec', 'hard', 'ambiguous', 'scope,interpretation');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-010', 'dataset-verification-judge-v1',
  json('{"artifact": "dependency-verifier testing a claim about an API that requires authentication", "spec_requirements": ["test against real implementations", "cite evidence with URLs", "provide confidence score"], "implementation_summary": "Verifier reports UNTESTABLE with confidence 0.25 because the API requires authentication and no credentials are available. Spec says test real implementations but does not address cases where testing requires credentials the agent does not have."}'),
  json('{"expected_verdict": "ESCALATE", "reason": "Spec gap: dependency-verifier is told to test real implementations but some implementations require credentials. The UNTESTABLE result is reasonable but the spec should explicitly address this case.", "blocking_issues": [], "advisory_issues": [{"description": "Agent spec should address credential-gated APIs — when to report UNTESTABLE vs request credentials vs use alternative verification methods"}]}'),
  'synthetic-from-spec', 'medium', 'ambiguous', 'spec-gap,credentials');

-- Category: style-only (2 — should VERIFY with advisory, NOT reject)

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-011', 'dataset-verification-judge-v1',
  json('{"artifact": "eval hook using inconsistent variable naming", "spec_requirements": ["3 graders implemented", "results logged to SQLite", "exit 0 on success"], "implementation_summary": "All 3 graders work correctly. Results logged. Exit codes correct. But variable names mix UPPER_CASE and camelCase conventions (e.g., TRANSCRIPT vs formatScore). Functionally correct."}'),
  json('{"expected_verdict": "VERIFIED", "pass1_deterministic": "All checks pass", "pass2_spec": "All requirements met", "pass3_perspectives": {"architect": "Inconsistent naming convention (advisory)"}, "blocking_issues": [], "advisory_issues": [{"description": "Variable naming inconsistent: TRANSCRIPT (uppercase) vs formatScore (camelCase). Recommend standardizing to UPPER_CASE for shell variables.", "severity": "style"}]}'),
  'synthetic-from-spec', 'easy', 'style-only', 'naming,style,advisory');

INSERT OR IGNORE INTO eval_examples (id, dataset_id, input, reference_output, provenance, difficulty, category, tags)
VALUES ('example-judge-012', 'dataset-verification-judge-v1',
  json('{"artifact": "seed-eval-data.sql with verbose comments", "spec_requirements": ["insert datasets for 5 agents", "insert examples with required fields", "insert grader registrations"], "implementation_summary": "All data inserts are correct and complete. File has extensive block comments explaining each section. Comments are longer than the actual SQL in some cases. Functionally perfect."}'),
  json('{"expected_verdict": "VERIFIED", "pass1_deterministic": "SQL valid, all inserts succeed", "pass2_spec": "All required data present", "pass3_perspectives": {"architect": "Comments are verbose but not harmful (advisory)"}, "blocking_issues": [], "advisory_issues": [{"description": "Comments exceed the code volume in several sections. Consider trimming to essential context only.", "severity": "style"}]}'),
  'synthetic-from-spec', 'easy', 'style-only', 'comments,verbosity,advisory');


-- ============================================================================
-- GRADERS: Code-based grader registration (13 graders)
-- ============================================================================

-- triage-fix graders (3)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('triage_format_compliance', 'triage-fix', 'code',
  'Checks that triage output contains all 6 required sections: Root cause, Classification, Fix applied, Before evidence, After evidence, Regression check',
  json('{"script": ".claude/hooks/eval-triage-fix.sh", "sections": ["Root cause", "Classification", "Fix applied", "Before evidence", "After evidence", "Regression check"], "threshold": 6}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('triage_scope_compliance', 'triage-fix', 'code',
  'Checks that file edit count stays within scope. Flags if more than 10 file edits detected (possible scope creep)',
  json('{"script": ".claude/hooks/eval-triage-fix.sh", "max_edits": 10}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('triage_escalation_judgment', 'triage-fix', 'code',
  'When external dependency is mentioned in transcript, checks that escalation was also mentioned. Binary pass/fail.',
  json('{"script": ".claude/hooks/eval-triage-fix.sh", "trigger_pattern": "external dependency|external dep", "expected_pattern": "escalat"}'),
  0.0);

-- research-taste graders (3)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('taste_verdict_valid', 'research-taste', 'code',
  'Checks that a valid verdict enum appears in output: proceed, simplify, defer, or kill',
  json('{"script": ".claude/hooks/eval-research-taste.sh", "valid_verdicts": ["proceed", "simplify", "defer", "kill"]}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('taste_format_compliance', 'research-taste', 'code',
  'Checks that output contains required sections: Verdict, rationale, Compression',
  json('{"script": ".claude/hooks/eval-research-taste.sh", "sections": ["Verdict", "rationale", "Compression"]}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('taste_compression_quality', 'research-taste', 'code',
  'Checks that compression field is a single sentence between 10-200 characters',
  json('{"script": ".claude/hooks/eval-research-taste.sh", "min_length": 10, "max_length": 200}'),
  0.0);

-- dependency-verifier graders (3)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('verifier_format_compliance', 'dependency-verifier', 'code',
  'Checks for 8-field assumption template: Assumption, Criticality, Source, Test, Result, Confidence, Evidence, Impact. Passes if 6+ found.',
  json('{"script": ".claude/hooks/eval-dependency-verifier.sh", "sections": ["Assumption", "Criticality", "Source", "Test", "Result", "Confidence", "Evidence", "Impact"], "threshold": 6}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('verifier_sources_cited', 'dependency-verifier', 'code',
  'Checks that at least one source URL (http/https) appears in the verification output',
  json('{"script": ".claude/hooks/eval-dependency-verifier.sh", "min_urls": 1}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('verifier_escalation_fields', 'dependency-verifier', 'code',
  'When FAILED+HIGH criticality detected, checks for 2+ options/alternatives/workarounds in escalation',
  json('{"script": ".claude/hooks/eval-dependency-verifier.sh", "trigger": "Result.*FAILED AND Criticality.*HIGH", "min_options": 2}'),
  0.0);

-- coordination-momentum graders (2)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('coord_sections_present', 'coordination-momentum', 'code',
  'Checks for 6 required report sections: Active, Blocked, Available, Conflict, Spiral, Recommend. Passes if 5+ found.',
  json('{"script": ".claude/hooks/eval-coordination-momentum.sh", "sections": ["Active", "Blocked", "Available", "Conflict", "Spiral", "Recommend"], "threshold": 5}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('coord_no_reprioritization', 'coordination-momentum', 'code',
  'Checks that recommendations do not attempt to change priority levels. Fails if reprioritization language detected.',
  json('{"script": ".claude/hooks/eval-coordination-momentum.sh", "forbidden_patterns": ["change.*priorit", "reprioritiz", "raise.*priority", "lower.*priority"]}'),
  0.0);

-- verification-judge graders (2 code + 1 trajectory = 3 total, but trajectory registered separately)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('judge_format_compliance', 'verification-judge', 'code',
  'Checks for 3-pass structure (Pass 1/Deterministic, Pass 2/Spec Compliance, Pass 3/Perspective) plus Verdict in output',
  json('{"script": ".claude/hooks/eval-verification-judge.sh", "sections": ["Pass 1|Deterministic", "Pass 2|Spec Compliance", "Pass 3|Perspective", "Verdict.*(VERIFIED|REJECTED|ESCALATE)"]}'),
  0.0);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, config, cost_estimate_usd)
VALUES ('judge_deterministic_first', 'verification-judge', 'trajectory',
  'Verifies that Pass 1 appears before Pass 2 and Pass 3 in the transcript. Trajectory check — operational ordering, not just output format.',
  json('{"script": ".claude/hooks/eval-verification-judge.sh", "check": "line_position", "required_order": ["Pass 1|Deterministic", "Pass 2|Spec Compliance", "Pass 3|Perspective"]}'),
  0.0);


-- ============================================================================
-- GRADERS: LLM-as-judge (model-based) grader registration (9 graders)
-- Phase 3: These use Haiku as the judge model (~$0.001/eval)
-- ============================================================================

-- triage-fix model graders (2)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('triage_root_cause_quality', 'triage-fix', 'model',
  'Evaluates whether the root cause explanation matches the actual fix and is specific enough to prevent recurrence',
  'claude-haiku-4-5-20251001',
  'You are evaluating a triage-fix agent''s root cause analysis.

Given:
- The failure description: {{input.failure_description}}
- The agent''s stated root cause: {{agent_output.root_cause}}
- The fix that was applied: {{agent_output.fix}}
- Files modified: {{agent_output.scope_files}}

Evaluate on two criteria:
1. MATCH: Does the root cause logically explain the failure AND does the fix address the root cause (not just the symptom)?
2. SPECIFICITY: Is the root cause specific enough that someone reading it could prevent similar failures?

Score 0.0-1.0:
- 1.0: Root cause matches fix perfectly, is specific and preventative
- 0.7: Root cause matches fix but is somewhat vague
- 0.4: Root cause is partially correct but fix addresses a different aspect
- 0.0: Root cause does not match the fix at all

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "match": <bool>, "specific": <bool>}',
  0.001);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('triage_escalation_judgment_llm', 'triage-fix', 'model',
  'For external dependency issues: did the agent correctly identify when to escalate vs fix?',
  'claude-haiku-4-5-20251001',
  'You are evaluating a triage-fix agent''s escalation judgment.

Given:
- The failure: {{input.failure_description}}
- The agent''s classification: {{agent_output.classification}}
- Whether the agent escalated: {{agent_output.should_escalate}}
- The expected classification: {{reference_output.classification}}

The triage-fix agent MUST escalate (not attempt a fix) when:
1. The root cause is an external dependency that doesn''t work as documented
2. The issue requires credentials, permissions, or infrastructure the agent cannot modify
3. The fix would require changing product scope

Did the agent make the correct escalation decision?

Score:
- 1.0: Correct decision (escalated when should have, or fixed when fixable)
- 0.0: Incorrect decision (attempted fix on external dep, or escalated fixable bug)

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "correct_decision": <bool>}',
  0.001);

-- research-taste model graders (2)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('taste_reasoning_quality', 'research-taste', 'model',
  'Evaluates whether the rationale logically supports the verdict',
  'claude-haiku-4-5-20251001',
  'You are evaluating a research-taste agent''s reasoning quality.

Given:
- The proposal: {{input.proposal}}
- The context: {{input.context}}
- The verdict: {{agent_output.verdict}} (one of: proceed, simplify, defer, kill)
- The rationale: {{agent_output.rationale}}
- The compression: {{agent_output.compression}}

Evaluate:
1. Does the rationale LOGICALLY SUPPORT the verdict? (Not just restate it)
2. Could the same rationale equally support a different verdict? (If yes, the reasoning is too vague)
3. Does the compression accurately capture the core insight?

Score 0.0-1.0:
- 1.0: Rationale uniquely supports the verdict with specific reasoning
- 0.7: Rationale supports the verdict but could also support an alternative
- 0.4: Rationale is relevant but does not clearly lead to the verdict
- 0.0: Rationale contradicts or is disconnected from the verdict

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "supports_verdict": <bool>, "uniquely_supports": <bool>}',
  0.001);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('taste_landscape_completeness', 'research-taste', 'model',
  'For evaluations with landscape assessment: did it find the most relevant adjacent work?',
  'claude-haiku-4-5-20251001',
  'You are evaluating a research-taste agent''s landscape assessment.

Given:
- The proposal: {{input.proposal}}
- The landscape assessment: {{agent_output.landscape}}
- The context: {{input.context}}

Evaluate:
1. Does the landscape identify the most relevant EXISTING work in this area?
2. Are there obvious gaps — major projects, papers, or tools that should have been mentioned?
3. Does the landscape assessment inform the verdict (is it load-bearing or decorative)?

Score 0.0-1.0:
- 1.0: Comprehensive landscape, no obvious gaps, directly informs the verdict
- 0.7: Good landscape but missing 1-2 relevant references
- 0.4: Superficial landscape, major gaps
- 0.0: No landscape or completely irrelevant references

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "gaps_found": [<string>]}',
  0.001);

-- dependency-verifier model graders (2)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('verifier_evidence_quality', 'dependency-verifier', 'model',
  'Evaluates whether the cited evidence actually supports the stated verification result',
  'claude-haiku-4-5-20251001',
  'You are evaluating a dependency-verifier agent''s evidence quality.

Given:
- The claim: {{input.claim}}
- The verification result: {{agent_output.result}} (VERIFIED, FAILED, PARTIAL, UNTESTABLE)
- The evidence cited: {{agent_output.evidence}}
- The confidence score: {{agent_output.confidence}}

Evaluate:
1. Does the evidence ACTUALLY SUPPORT the stated result? (Not just tangentially related)
2. Is the evidence from the right source? (Implementation test, not just docs)
3. Is the confidence score calibrated? (High confidence should mean strong evidence)

Score 0.0-1.0:
- 1.0: Evidence directly supports result, from authoritative source, confidence calibrated
- 0.7: Evidence supports result but from secondary source or confidence slightly miscalibrated
- 0.4: Evidence is tangential or from unreliable source
- 0.0: Evidence contradicts the result or is fabricated

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "evidence_supports_result": <bool>, "confidence_calibrated": <bool>}',
  0.001);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('verifier_test_rigor', 'dependency-verifier', 'model',
  'Evaluates whether verification tested real implementations, not just documentation',
  'claude-haiku-4-5-20251001',
  'You are evaluating a dependency-verifier agent''s test methodology.

Given:
- The claim: {{input.claim}}
- The test method described: {{agent_output.test_method}}
- The evidence: {{agent_output.evidence}}

The dependency-verifier MUST test against real, running implementations — not just read documentation. The core principle is: "what the spec says" vs "what the implementation does" are different things.

Evaluate:
1. Did the agent actually run code, call an API, or test a real system?
2. Or did it just read documentation and infer the answer?
3. If the claim was untestable, did the agent clearly explain WHY it could not test?

Score:
- 1.0: Tested against real implementation with observable evidence
- 0.5: Tested documentation thoroughly but did not run actual code
- 0.0: Only read docs without any verification attempt

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "tested_real_implementation": <bool>}',
  0.001);

-- coordination-momentum model grader (1)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('coord_recommendation_relevance', 'coordination-momentum', 'model',
  'Evaluates whether recommendations are appropriate for the current project state',
  'claude-haiku-4-5-20251001',
  'You are evaluating a coordination-momentum agent''s recommendations.

Given:
- The current project state: {{input.bd_list_output}}
- Blocked issues: {{input.bd_blocked_output}}
- Stats: {{input.bd_stats_output}}
- Recent git activity: {{input.git_log}}
- The agent''s recommendation: {{agent_output.expected_recommendation}}

The coordination agent MUST NOT reprioritize work. It CAN recommend which available work to pick up next, surface conflicts, and recommend escalation when all work is blocked.

Evaluate:
1. Are recommendations actionable and appropriate for the current state?
2. Do they respect priority ordering (higher priority first)?
3. Do they correctly identify the critical path?
4. Do they avoid overstepping (no reprioritization, no scope changes)?

Score 0.0-1.0:
- 1.0: Recommendations are actionable, respect priorities, identify critical path
- 0.7: Recommendations are reasonable but miss an important aspect
- 0.4: Recommendations are generic or partially inappropriate
- 0.0: Recommendations overstep boundaries or are counterproductive

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "respects_boundaries": <bool>, "identifies_critical_path": <bool>}',
  0.001);

-- verification-judge model graders (2)
INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('judge_rejection_quality', 'verification-judge', 'model',
  'For REJECTED verdicts: are the stated issues real problems or stylistic preferences?',
  'claude-haiku-4-5-20251001',
  'You are evaluating a verification-judge agent''s rejection reasoning.

Given:
- The artifact being verified: {{input.artifact}}
- The spec requirements: {{input.spec_requirements}}
- The verdict: REJECTED
- The blocking issues listed: {{agent_output.blocking_issues}}
- The advisory issues: {{agent_output.advisory_issues}}

The verification-judge MUST distinguish between:
- Blocking issues: real bugs, spec violations, security issues (warrant REJECT)
- Advisory issues: style preferences, minor improvements (warrant VERIFY with advisory)

Evaluate each blocking issue:
1. Is it a REAL problem (bug, spec violation, security risk)?
2. Or is it a STYLE preference (naming, comments, formatting)?
3. Would this issue cause actual failures in production?

Score 0.0-1.0:
- 1.0: All blocking issues are genuine problems that would cause failures
- 0.7: Most blocking issues are real but 1 is borderline style
- 0.4: Mix of real issues and style preferences in blocking list
- 0.0: All "blocking" issues are actually style preferences (should be VERIFIED with advisory)

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "real_issues": [<string>], "style_issues": [<string>]}',
  0.001);

INSERT OR IGNORE INTO eval_graders (id, agent_name, grader_type, description, judge_model, judge_prompt, cost_estimate_usd)
VALUES ('judge_perspective_coverage', 'verification-judge', 'model',
  'Evaluates whether the 4 perspectives cover distinct concerns without overlap',
  'claude-haiku-4-5-20251001',
  'You are evaluating a verification-judge agent''s perspective review (Pass 3).

Given:
- The artifact: {{input.artifact}}
- Pass 3 perspectives:
  - Logician: {{agent_output.pass3_perspectives.logician}}
  - Architect: {{agent_output.pass3_perspectives.architect}}
  - Security Guardian: {{agent_output.pass3_perspectives.security}}
  - Implementer: {{agent_output.pass3_perspectives.implementer}}

The 4 perspectives MUST cover DISTINCT concerns. If the Logician and Architect both flag "inconsistent naming" that is overlapping, not complementary.

Evaluate:
1. Does each perspective raise concerns unique to its viewpoint?
2. Is there significant overlap (same issue raised by 2+ perspectives)?
3. Are any perspectives empty/trivial (just saying "looks good")?

Score 0.0-1.0:
- 1.0: All 4 perspectives raise distinct, substantive concerns
- 0.7: 3 perspectives distinct, 1 overlaps with another
- 0.4: Significant overlap between perspectives
- 0.0: All perspectives raise the same concern or are trivial

Respond with JSON: {"score": <float>, "reasoning": "<1-2 sentences>", "distinct_count": <int>, "overlapping_pairs": [<string>]}',
  0.001);


-- ============================================================================
-- VERIFICATION QUERIES (run after loading to confirm data integrity)
-- ============================================================================

-- Uncomment to verify:
-- SELECT 'datasets' AS table_name, count(*) AS row_count FROM eval_datasets
-- UNION ALL SELECT 'examples', count(*) FROM eval_examples
-- UNION ALL SELECT 'graders', count(*) FROM eval_graders;
--
-- Expected: datasets=5, examples=59, graders=13
--
-- SELECT agent_name, count(*) AS example_count FROM eval_examples e
-- JOIN eval_datasets d ON e.dataset_id = d.id
-- GROUP BY agent_name;
--
-- Expected: triage-fix=10, research-taste=15, dependency-verifier=12,
--           coordination-momentum=10, verification-judge=12
--
-- SELECT agent_name, grader_type, count(*) FROM eval_graders GROUP BY agent_name, grader_type;
--
-- Expected: 13 total across 5 agents
