-- 02_explain_analyze.sql
-- Purpose: Demonstrate the effect of analytical (covering) indexes on the
-- four SELECTIVE queries from 01_queries.sql. The script:
--   1. drops the P2 analytical indexes,
--   2. runs EXPLAIN (ANALYZE, BUFFERS) for Q1-Q4 BEFORE the indexes,
--   3. (re)creates the P2 indexes,
--   4. runs EXPLAIN (ANALYZE, BUFFERS) for Q1-Q4 AFTER the indexes.
-- The four FULL-TABLE aggregates (Q5-Q8) are NOT re-explained here on
-- purpose -- they are designed to keep a Seq Scan (see README).
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 02_explain_analyze.sql

SET timezone TO 'Africa/Lagos';
\pset pager off
\timing off

-- =====================================================================
-- STEP 1: drop the P2 analytical indexes if they exist.
-- =====================================================================
DROP INDEX IF EXISTS p2_idx_transcript;
DROP INDEX IF EXISTS p2_idx_result_sheet;
DROP INDEX IF EXISTS p2_idx_lecturer_courses;
DROP INDEX IF EXISTS p2_idx_recent_audit;
DROP INDEX IF EXISTS p2_idx_recent_result;

-- Make sure planner stats are fresh on the FK-only indexes from P1.
ANALYZE assessment_result;
ANALYZE result_batch;
ANALYZE grade_change_audit;
ANALYZE lecturer;
ANALYZE student;
ANALYZE course;
ANALYZE semester;
ANALYZE programme;

-- =====================================================================
-- STEP 2: BEFORE the P2 indexes -- EXPLAIN (ANALYZE, BUFFERS) for Q1-Q4.
-- =====================================================================

\echo '==== BEFORE P2 indexes ===='
\echo '---- Q1: transcript for ICU/2023/00001 ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.matric_no, c.code, c.title, ar.total_score, ar.grade, ar.grade_point
FROM student s
JOIN assessment_result ar ON ar.matric_no = s.matric_no
JOIN course c ON c.course_id = ar.course_id
JOIN semester sem ON sem.semester_id = ar.semester_id
WHERE s.matric_no = 'ICU/2023/00001'
  AND ar.superseded = FALSE
  AND ar.status IN ('APPROVED', 'PUBLISHED')
ORDER BY sem.start_date, c.code;

\echo '---- Q2: result sheet for the first PUBLISHED batch of CSC101 ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT ar.matric_no, ar.total_score, ar.grade, ar.grade_point, ar.status
FROM assessment_result ar
WHERE ar.batch_id = (
    SELECT rb2.batch_id
    FROM result_batch rb2
    JOIN course c2 ON c2.course_id = rb2.course_id
    WHERE c2.code = 'CSC101' AND rb2.status = 'PUBLISHED'
    ORDER BY rb2.batch_id LIMIT 1
)
ORDER BY ar.total_score DESC;

\echo '---- Q3: courses taught by ICU/STAFF/001 ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.staff_no, sem.session, sem.term, c.code, rb.batch_id, rb.status,
       COUNT(ar.result_id) AS students_in_batch
FROM lecturer l
JOIN result_batch rb ON rb.lecturer_id = l.lecturer_id
JOIN course c ON c.course_id = rb.course_id
JOIN semester sem ON sem.semester_id = rb.semester_id
LEFT JOIN assessment_result ar ON ar.batch_id = rb.batch_id
WHERE l.staff_no = 'ICU/STAFF/001'
GROUP BY l.staff_no, sem.session, sem.term, sem.start_date, c.code, rb.batch_id, rb.status
ORDER BY sem.start_date, c.code;

\echo '---- Q4: changes in the last 30 days ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT change_time, matric_no, course_code
FROM (
    SELECT gca.created_at AS change_time, ar.matric_no, c.code AS course_code
    FROM grade_change_audit gca
    JOIN assessment_result ar ON ar.result_id = gca.result_id
    JOIN course c ON c.course_id = ar.course_id
    WHERE gca.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    UNION ALL
    SELECT ar.updated_at AS change_time, ar.matric_no, c.code AS course_code
    FROM assessment_result ar
    JOIN course c ON c.course_id = ar.course_id
    WHERE ar.updated_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
      AND ar.updated_at <> ar.created_at
) ch
ORDER BY change_time DESC
LIMIT 200;

-- =====================================================================
-- STEP 3: create the P2 analytical (covering) indexes.
-- These carry INCLUDE columns so the planner can do Index-Only Scans
-- without touching the heap.
-- =====================================================================

-- Q1 transcript: covering index on matric_no, filtered to active results.
CREATE INDEX IF NOT EXISTS p2_idx_transcript
    ON assessment_result (matric_no)
    INCLUDE (course_id, semester_id, ca_score, exam_score,
             total_score, grade, grade_point, status)
    WHERE superseded = FALSE AND status IN ('APPROVED', 'PUBLISHED');

-- Q2 result sheet: covering index on batch_id.
CREATE INDEX IF NOT EXISTS p2_idx_result_sheet
    ON assessment_result (batch_id)
    INCLUDE (matric_no, ca_score, exam_score, total_score,
             grade, grade_point, status);

-- Q3 lecturer courses: covering index on result_batch(lecturer_id).
CREATE INDEX IF NOT EXISTS p2_idx_lecturer_courses
    ON result_batch (lecturer_id)
    INCLUDE (course_id, semester_id, batch_id, status);

-- Q4 last-30-days: covering indexes on the two timestamp columns.
CREATE INDEX IF NOT EXISTS p2_idx_recent_audit
    ON grade_change_audit (created_at)
    INCLUDE (result_id, changed_by, reason, old_grade, new_grade,
             old_total_score, new_total_score);

CREATE INDEX IF NOT EXISTS p2_idx_recent_result
    ON assessment_result (updated_at)
    INCLUDE (matric_no, course_id, status, grade, ca_score, exam_score, total_score)
    WHERE updated_at <> created_at;

-- Refresh planner stats so the AFTER plans use the new indexes.
ANALYZE assessment_result;
ANALYZE result_batch;
ANALYZE grade_change_audit;

-- =====================================================================
-- STEP 4: AFTER the P2 indexes -- re-run EXPLAIN (ANALYZE, BUFFERS).
-- =====================================================================

\echo '==== AFTER P2 indexes ===='
\echo '---- Q1: transcript for ICU/2023/00001 ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT s.matric_no, c.code, c.title, ar.total_score, ar.grade, ar.grade_point
FROM student s
JOIN assessment_result ar ON ar.matric_no = s.matric_no
JOIN course c ON c.course_id = ar.course_id
JOIN semester sem ON sem.semester_id = ar.semester_id
WHERE s.matric_no = 'ICU/2023/00001'
  AND ar.superseded = FALSE
  AND ar.status IN ('APPROVED', 'PUBLISHED')
ORDER BY sem.start_date, c.code;

\echo '---- Q2: result sheet for the first PUBLISHED batch of CSC101 ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT ar.matric_no, ar.total_score, ar.grade, ar.grade_point, ar.status
FROM assessment_result ar
WHERE ar.batch_id = (
    SELECT rb2.batch_id
    FROM result_batch rb2
    JOIN course c2 ON c2.course_id = rb2.course_id
    WHERE c2.code = 'CSC101' AND rb2.status = 'PUBLISHED'
    ORDER BY rb2.batch_id LIMIT 1
)
ORDER BY ar.total_score DESC;

\echo '---- Q3: courses taught by ICU/STAFF/001 ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.staff_no, sem.session, sem.term, c.code, rb.batch_id, rb.status,
       COUNT(ar.result_id) AS students_in_batch
FROM lecturer l
JOIN result_batch rb ON rb.lecturer_id = l.lecturer_id
JOIN course c ON c.course_id = rb.course_id
JOIN semester sem ON sem.semester_id = rb.semester_id
LEFT JOIN assessment_result ar ON ar.batch_id = rb.batch_id
WHERE l.staff_no = 'ICU/STAFF/001'
GROUP BY l.staff_no, sem.session, sem.term, sem.start_date, c.code, rb.batch_id, rb.status
ORDER BY sem.start_date, c.code;

\echo '---- Q4: changes in the last 30 days ----'
EXPLAIN (ANALYZE, BUFFERS)
SELECT change_time, matric_no, course_code
FROM (
    SELECT gca.created_at AS change_time, ar.matric_no, c.code AS course_code
    FROM grade_change_audit gca
    JOIN assessment_result ar ON ar.result_id = gca.result_id
    JOIN course c ON c.course_id = ar.course_id
    WHERE gca.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
    UNION ALL
    SELECT ar.updated_at AS change_time, ar.matric_no, c.code AS course_code
    FROM assessment_result ar
    JOIN course c ON c.course_id = ar.course_id
    WHERE ar.updated_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
      AND ar.updated_at <> ar.created_at
) ch
ORDER BY change_time DESC
LIMIT 200;

-- =====================================================================
-- Reminder for the README: the four full-table aggregates (Q5-Q8) are
-- deliberately not re-explained here. They scan most of assessment_result
-- and stay on Seq Scan -- adding an index would not help them.
-- =====================================================================
\echo '==== Done. Full-table aggregates (Q5-Q8) keep a Seq Scan -- see README. ===='
