-- 01_queries.sql
-- Purpose: The eight reporting queries that exercise the Ibom Crown
-- schema. 4 selective (single-student transcript, single-batch result
-- sheet, single-lecturer course list, last 30 days of changes) and
-- 4 full-table aggregates (pass rate per department, grade distribution
-- per course, average CGPA per programme, academic-standing counts per
-- department). Queries 1-4 are the ones re-explained in 02_explain_analyze.sql.
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 01_queries.sql

SET timezone TO 'Africa/Lagos';
\pset pager off

-- =====================================================================
-- Q1  SELECTIVE: a student's transcript across all semesters
--     (uses idx_assessment_result_matric_no)
-- =====================================================================
\echo '---- Q1: transcript for ICU/2023/00001 ----'
SELECT
    s.matric_no,
    s.first_name || ' ' || s.last_name                AS student_name,
    p.code                                           AS programme_code,
    p.name                                           AS programme_name,
    sem.session,
    sem.term,
    c.code                                           AS course_code,
    c.title                                          AS course_title,
    c.credit_units,
    ar.ca_score,
    ar.exam_score,
    ar.total_score,
    ar.grade,
    ar.grade_point
FROM student           s
JOIN programme         p   ON p.programme_id  = s.programme_id
JOIN assessment_result ar  ON ar.matric_no    = s.matric_no
JOIN course            c   ON c.course_id     = ar.course_id
JOIN semester          sem ON sem.semester_id = ar.semester_id
WHERE s.matric_no = 'ICU/2023/00001'
  AND ar.superseded = FALSE
  AND ar.status IN ('APPROVED', 'PUBLISHED')
ORDER BY sem.start_date, c.code;

-- Semester GPA for the same student (uses v_semester_summary)
SELECT
    vss.session, vss.term,
    vss.total_credits,
    ROUND(vss.gpa, 2)               AS gpa,
    vss.carry_over_count
FROM v_semester_summary vss
WHERE vss.matric_no = 'ICU/2023/00001'
ORDER BY vss.session, vss.term;

-- Cumulative CGPA + standing
SELECT
    vcs.cgpa,
    vcs.graduation_class,
    vcs.academic_standing,
    vcs.total_credits,
    vcs.total_carry_overs
FROM v_cgpa_summary vcs
WHERE vcs.matric_no = 'ICU/2023/00001';

-- =====================================================================
-- Q2  SELECTIVE: a course's result sheet (one batch)
--     (uses idx_assessment_result_batch_id)
-- =====================================================================
\echo '---- Q2: result sheet for the first PUBLISHED batch of CSC101 ----'
SELECT
    rb.batch_id,
    c.code    AS course_code,
    c.title   AS course_title,
    sem.session,
    sem.term,
    l.staff_no,
    l.first_name || ' ' || l.last_name AS lecturer_name,
    rb.status AS batch_status
FROM result_batch rb
JOIN course    c   ON c.course_id   = rb.course_id
JOIN semester  sem ON sem.semester_id = rb.semester_id
JOIN lecturer  l   ON l.lecturer_id = rb.lecturer_id
WHERE rb.batch_id = (
    SELECT rb2.batch_id
    FROM result_batch rb2
    JOIN course c2 ON c2.course_id = rb2.course_id
    WHERE c2.code = 'CSC101' AND rb2.status = 'PUBLISHED'
    ORDER BY rb2.batch_id LIMIT 1
);

SELECT
    ar.matric_no,
    st.first_name || ' ' || st.last_name AS student_name,
    st.gender,
    ar.ca_score,
    ar.exam_score,
    ar.total_score,
    ar.grade,
    ar.grade_point,
    ar.status
FROM assessment_result ar
JOIN student st ON st.matric_no = ar.matric_no
WHERE ar.batch_id = (
    SELECT rb2.batch_id
    FROM result_batch rb2
    JOIN course c2 ON c2.course_id = rb2.course_id
    WHERE c2.code = 'CSC101' AND rb2.status = 'PUBLISHED'
    ORDER BY rb2.batch_id LIMIT 1
)
ORDER BY ar.total_score DESC;

-- =====================================================================
-- Q3  SELECTIVE: a lecturer's courses across all semesters
--     (uses idx_result_batch_lecturer_id)
-- =====================================================================
\echo '---- Q3: courses taught by ICU/STAFF/001 ----'
SELECT
    l.staff_no,
    l.title || ' ' || l.first_name || ' ' || l.last_name AS lecturer_name,
    d.name AS department,
    sem.session,
    sem.term,
    c.code AS course_code,
    c.title AS course_title,
    c.credit_units,
    rb.batch_id,
    rb.status AS batch_status,
    COUNT(ar.result_id) AS students_in_batch
FROM lecturer l
JOIN department   d   ON d.dept_id      = l.dept_id
JOIN result_batch rb  ON rb.lecturer_id = l.lecturer_id
JOIN course       c   ON c.course_id    = rb.course_id
JOIN semester     sem ON sem.semester_id = rb.semester_id
LEFT JOIN assessment_result ar ON ar.batch_id = rb.batch_id
WHERE l.staff_no = 'ICU/STAFF/001'
GROUP BY l.staff_no, l.title, l.first_name, l.last_name, d.name,
         sem.session, sem.term, sem.start_date, c.code, c.title, c.credit_units, rb.batch_id, rb.status
ORDER BY sem.start_date, c.code;

-- =====================================================================
-- Q4  SELECTIVE: last 30 days of changes
--     (union of grade_change_audit + recently updated results)
--     Uses idx_grade_change_audit_created_at and idx_assessment_result_updated_at.
-- =====================================================================
\echo '---- Q4: result changes in the last 30 days ----'
SELECT change_type, change_time, matric_no, course_code, detail
FROM (
    SELECT
        'AUDIT'         AS change_type,
        gca.created_at  AS change_time,
        ar.matric_no    AS matric_no,
        c.code          AS course_code,
        (gca.changed_by || ' : ' || gca.reason ||
         ' (old ' || COALESCE(gca.old_grade, '?') || '/' || COALESCE(gca.old_total_score::text, '?') ||
         ' -> new ' || COALESCE(gca.new_grade, '?') || '/' || COALESCE(gca.new_total_score::text, '?') || ')') AS detail
    FROM grade_change_audit gca
    JOIN assessment_result ar ON ar.result_id = gca.result_id
    JOIN course c ON c.course_id = ar.course_id
    WHERE gca.created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'

    UNION ALL

    SELECT
        'RESULT_UPDATE' AS change_type,
        ar.updated_at   AS change_time,
        ar.matric_no    AS matric_no,
        c.code          AS course_code,
        ('auto-update, status=' || ar.status || ', grade=' || COALESCE(ar.grade, '?')) AS detail
    FROM assessment_result ar
    JOIN course c ON c.course_id = ar.course_id
    WHERE ar.updated_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'
      AND ar.updated_at <> ar.created_at
) ch
ORDER BY change_time DESC
LIMIT 200;

-- =====================================================================
-- Q5  AGGREGATE: pass rate per department
--     (full scan of assessment_result; keeps a Seq Scan)
-- =====================================================================
\echo '---- Q5: pass rate per department ----'
SELECT
    d.dept_code,
    d.name AS department,
    COUNT(*)                                            AS total_results,
    COUNT(*) FILTER (WHERE ar.grade <> 'F')             AS passed,
    COUNT(*) FILTER (WHERE ar.grade = 'F')              AS failed,
    ROUND(100.0 * COUNT(*) FILTER (WHERE ar.grade <> 'F') / NULLIF(COUNT(*), 0), 2)
                                                        AS pass_rate_pct
FROM assessment_result ar
JOIN course      c ON c.course_id  = ar.course_id
JOIN department  d ON d.dept_id    = c.dept_id
WHERE ar.status IN ('APPROVED', 'PUBLISHED')
  AND ar.superseded = FALSE
GROUP BY d.dept_id, d.dept_code, d.name
ORDER BY pass_rate_pct DESC;

-- =====================================================================
-- Q6  AGGREGATE: grade distribution per course
--     (full scan of assessment_result; keeps a Seq Scan)
-- =====================================================================
\echo '---- Q6: grade distribution per course ----'
SELECT
    c.code AS course_code,
    c.title,
    ar.grade,
    COUNT(*) AS student_count
FROM assessment_result ar
JOIN course c ON c.course_id = ar.course_id
WHERE ar.status IN ('APPROVED', 'PUBLISHED')
  AND ar.superseded = FALSE
GROUP BY c.code, c.title, ar.grade
ORDER BY c.code, ar.grade;

-- =====================================================================
-- Q7  AGGREGATE: average CGPA per programme
--     (full scan via the v_cgpa_summary view; keeps a Seq Scan)
-- =====================================================================
\echo '---- Q7: average CGPA per programme ----'
SELECT
    p.code AS programme_code,
    p.name AS programme_name,
    COUNT(*)               AS student_count,
    ROUND(AVG(vcs.cgpa), 2) AS avg_cgpa,
    ROUND(MIN(vcs.cgpa), 2) AS min_cgpa,
    ROUND(MAX(vcs.cgpa), 2) AS max_cgpa
FROM v_cgpa_summary vcs
JOIN programme p ON p.programme_id = vcs.programme_id
GROUP BY p.code, p.name
ORDER BY avg_cgpa DESC;

-- =====================================================================
-- Q8  AGGREGATE: academic-standing distribution per department
--     (full scan via v_cgpa_summary; keeps a Seq Scan)
-- =====================================================================
\echo '---- Q8: academic standing per department ----'
SELECT
    d.name AS department,
    COALESCE(vcs.academic_standing, 'No results') AS standing,
    COUNT(*) AS student_count
FROM v_cgpa_summary vcs
JOIN student    s ON s.matric_no    = vcs.matric_no
JOIN programme  p ON p.programme_id = s.programme_id
JOIN department d ON d.dept_id      = p.dept_id
GROUP BY d.name, vcs.academic_standing
ORDER BY d.name, standing;
