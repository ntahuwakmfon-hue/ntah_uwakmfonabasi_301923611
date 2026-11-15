# Portfolio 2 — Query Optimisation

**Database:** `resultsys` (PostgreSQL 16)

## What this portfolio does

Eight reporting queries against the Ibom Crown schema: four selective queries that benefit from indexes, and four full-table aggregate queries that scan most of `assessment_result` and stay on a `Seq Scan` by design.

`02_explain_analyze.sql` demonstrates the planner's behaviour on the four selective queries **before** and **after** five covering indexes are added. The aggregates are not re-explained — they would not benefit.

## Files

| File | What it does |
| --- | --- |
| `01_queries.sql` | 8 queries: Q1 transcript, Q2 result sheet, Q3 lecturer's courses, Q4 last 30 days of changes; Q5 pass rate per department, Q6 grade distribution per course, Q7 average CGPA per programme, Q8 academic standing per department. |
| `02_explain_analyze.sql` | Drops the P2 analytical indexes, runs `EXPLAIN (ANALYZE, BUFFERS)` for Q1–Q4, (re)creates five covering indexes, and re-runs the same four `EXPLAIN (ANALYZE, BUFFERS)`. |

## The eight queries

| # | Type | What it returns | Index it leans on |
| --- | --- | --- | --- |
| Q1 | selective | A student's full transcript (every course, every semester) plus semester GPA and CGPA | `assessment_result(matric_no)` (+ partial filter) |
| Q2 | selective | One batch's result sheet (all students, ranked by total score) | `assessment_result(batch_id)` |
| Q3 | selective | One lecturer's courses across all semesters, with batch status and student counts | `result_batch(lecturer_id)` |
| Q4 | selective | Last 30 days of changes (grade-change audit rows UNION recently updated results) | `grade_change_audit(created_at)` + `assessment_result(updated_at)` |
| Q5 | aggregate | Pass rate per department (passed / total, %) | Seq Scan |
| Q6 | aggregate | Grade distribution per course (A/B/C/D/E/F counts) | Seq Scan |
| Q7 | aggregate | Average / min / max CGPA per programme | Seq Scan on `v_cgpa_summary` |
| Q8 | aggregate | Academic-standing distribution per department | Seq Scan on `v_cgpa_summary` |

## P2 covering indexes (created in `02_explain_analyze.sql`)

```sql
CREATE INDEX p2_idx_transcript
    ON assessment_result (matric_no)
    INCLUDE (course_id, semester_id, ca_score, exam_score,
             total_score, grade, grade_point, status)
    WHERE superseded = FALSE AND status IN ('APPROVED', 'PUBLISHED');

CREATE INDEX p2_idx_result_sheet
    ON assessment_result (batch_id)
    INCLUDE (matric_no, ca_score, exam_score, total_score, grade, grade_point, status);

CREATE INDEX p2_idx_lecturer_courses
    ON result_batch (lecturer_id)
    INCLUDE (course_id, semester_id, batch_id, status);

CREATE INDEX p2_idx_recent_audit
    ON grade_change_audit (created_at)
    INCLUDE (result_id, changed_by, reason, old_grade, new_grade,
             old_total_score, new_total_score);

CREATE INDEX p2_idx_recent_result
    ON assessment_result (updated_at)
    INCLUDE (matric_no, course_id, status, grade, ca_score, exam_score, total_score)
    WHERE updated_at <> created_at;
```

The `INCLUDE` columns let the planner satisfy the queries with an **Index-Only Scan** instead of an Index Scan followed by heap fetches. The partial predicates (`WHERE superseded = FALSE AND status IN (...)`, `WHERE updated_at <> created_at`) keep the indexes small.

## Honest claim about performance

The selective queries (Q1–Q4) benefit from the P2 indexes — the AFTER plan typically switches to an **Index-Only Scan** and reads fewer buffers. **The full-table aggregates (Q5–Q8) do not benefit:** they touch most rows in `assessment_result`, so the planner correctly keeps a `Seq Scan`. Adding a B-tree index to "help" them would only waste disk and write amplification, which is exactly what we do not want on the biggest table.

In other words: **not every query gets faster.** Selective point lookups get faster; full-table aggregates stay on `Seq Scan`.

## How to run

```bash
psql -d resultsys -v ON_ERROR_STOP=1 -f 01_queries.sql
psql -d resultsys -v ON_ERROR_STOP=1 -f 02_explain_analyze.sql
```

## EXPLAIN ANALYZE output

Paste the BEFORE and AFTER plans for Q1–Q4 below:

```
[paste real output here]
```
