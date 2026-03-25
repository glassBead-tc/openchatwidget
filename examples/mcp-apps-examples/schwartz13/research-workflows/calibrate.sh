#!/bin/bash
# calibrate.sh — Human calibration tool for eval graders
#
# Displays eval results and collects human scores for grader_calibration.
# Run quarterly: 5 examples per agent = 25 total reviews.
#
# Usage: ./research-workflows/calibrate.sh [calibration_round]
#   calibration_round defaults to current quarter (e.g., "2026-Q1")
#
# Thresholds (from spec):
#   > 80% agreement: Grader trusted
#   60-80%: Review and refine judge prompt
#   < 60%: Grader unreliable, fall back to human

set -euo pipefail

DB_PATH="$(dirname "$0")/workflows.db"
ROUND="${1:-$(date +%Y-Q)$(( ($(date +%-m) - 1) / 3 + 1 ))}"

if [ ! -f "$DB_PATH" ]; then
  echo "Error: $DB_PATH not found"
  exit 1
fi

echo "=== Human Calibration Review ==="
echo "Round: $ROUND"
echo "Database: $DB_PATH"
echo ""

# Get 5 recent eval results per agent (25 total) that haven't been calibrated this round
RESULTS=$(sqlite3 -separator '|' "$DB_PATH" "
  SELECT r.id, r.grader_id, g.agent_name, r.score, r.passed, r.comment,
         SUBSTR(r.agent_output, 1, 300) AS output_preview,
         r.example_id
  FROM eval_results r
  JOIN eval_graders g ON g.id = r.grader_id
  WHERE r.id NOT IN (
    SELECT DISTINCT r2.id FROM eval_results r2
    JOIN grader_calibration c ON c.grader_id = r2.grader_id
      AND c.example_id = r2.example_id
      AND c.calibration_round = '$ROUND'
  )
  ORDER BY g.agent_name, r.created_at DESC
  LIMIT 25
")

if [ -z "$RESULTS" ]; then
  echo "No uncalibrated results found for round $ROUND."
  echo ""
  echo "Current calibration summary:"
  sqlite3 -header -column "$DB_PATH" "SELECT * FROM grader_calibration_summary WHERE calibration_round = '$ROUND';" 2>/dev/null || echo "(no data yet)"
  exit 0
fi

REVIEWED=0
AGREED=0

while IFS='|' read -r RESULT_ID GRADER_ID AGENT_NAME GRADER_SCORE GRADER_PASSED COMMENT OUTPUT_PREVIEW EXAMPLE_ID; do
  echo "────────────────────────────────────────"
  echo "Agent: $AGENT_NAME"
  echo "Grader: $GRADER_ID"
  echo "Grader Score: $GRADER_SCORE (passed=$GRADER_PASSED)"
  echo "Grader Comment: $COMMENT"
  echo ""
  echo "Agent Output Preview:"
  echo "$OUTPUT_PREVIEW"
  echo ""

  # Prompt for human score
  read -rp "Your score (0.0-1.0, or 's' to skip, 'q' to quit): " HUMAN_SCORE
  if [ "$HUMAN_SCORE" = "q" ]; then
    break
  fi
  if [ "$HUMAN_SCORE" = "s" ]; then
    echo "Skipped."
    echo ""
    continue
  fi

  HUMAN_PASSED=$( echo "$HUMAN_SCORE >= 0.5" | bc -l 2>/dev/null && echo 1 || echo 0 )
  # Recalculate properly
  if (( $(echo "$HUMAN_SCORE >= 0.5" | bc -l 2>/dev/null || echo 0) )); then
    HUMAN_PASSED=1
  else
    HUMAN_PASSED=0
  fi

  read -rp "Brief notes (optional): " HUMAN_NOTES

  # Check agreement
  SCORES_AGREE=0
  if [ "$HUMAN_PASSED" -eq "$GRADER_PASSED" ]; then
    SCORES_AGREE=1
    AGREED=$((AGREED + 1))
  fi
  SCORE_DELTA=$(echo "scale=3; $GRADER_SCORE - $HUMAN_SCORE" | bc | sed 's/^-//')

  # Insert into grader_calibration
  sqlite3 "$DB_PATH" "INSERT INTO grader_calibration
    (grader_id, example_id, grader_score, grader_passed, human_score, human_passed,
     human_notes, scores_agree, score_delta, calibration_round)
    VALUES ('$GRADER_ID', '$EXAMPLE_ID', $GRADER_SCORE, $GRADER_PASSED,
            $HUMAN_SCORE, $HUMAN_PASSED, '$HUMAN_NOTES', $SCORES_AGREE, $SCORE_DELTA, '$ROUND');"

  REVIEWED=$((REVIEWED + 1))
  echo "Recorded. Agreement: $([ "$SCORES_AGREE" -eq 1 ] && echo 'YES' || echo 'NO')"
  echo ""
done <<< "$RESULTS"

echo ""
echo "=== Calibration Summary ==="
echo "Reviewed: $REVIEWED"
if [ "$REVIEWED" -gt 0 ]; then
  AGREEMENT_RATE=$(echo "scale=1; $AGREED * 100 / $REVIEWED" | bc)
  echo "Agreement: $AGREED/$REVIEWED (${AGREEMENT_RATE}%)"
  echo ""

  if (( $(echo "$AGREEMENT_RATE > 80" | bc -l) )); then
    echo "Status: TRUSTED (>80% agreement)"
  elif (( $(echo "$AGREEMENT_RATE >= 60" | bc -l) )); then
    echo "Status: REVIEW NEEDED (60-80% agreement)"
  else
    echo "Status: UNRELIABLE (<60% — fall back to human grading)"
  fi
fi

echo ""
echo "Full calibration summary:"
sqlite3 -header -column "$DB_PATH" "SELECT * FROM grader_calibration_summary;" 2>/dev/null || echo "(no calibration data yet)"
