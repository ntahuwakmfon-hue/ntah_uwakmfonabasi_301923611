-- 04_bulk_data.sql
-- Purpose: Bulk-load realistic history for Ibom Crown University using
-- generate_series (no Python loops). Adds 2,000 students and ~60,000
-- assessment_result rows across 4 semesters, with PENDING/DRAFT results
-- only in the CURRENT semester. Past semesters are PUBLISHED.
-- Idempotent on students (ON CONFLICT DO NOTHING) but the result insert
-- is designed to be run ONCE after 03_seed_data.sql. Runs top to bottom
-- with: psql -d resultsys -v ON_ERROR_STOP=1 -f 04_bulk_data.sql
-- Target run time: well under 30 seconds on a Codespaces 2-core box.

SET timezone TO 'Africa/Lagos';

-- =====================================================================
-- 1. 2,000 more students (matric_no ICU/2024/00100 .. ICU/2024/02099)
-- Gender-matched Nigerian first names + Akwa Ibom / neighbouring states.
-- =====================================================================
INSERT INTO student
    (matric_no, programme_id, first_name, last_name, gender,
     level, status, session_admitted, state_of_origin, tuition_ngn)
SELECT
    'ICU/2024/' || lpad(g::text, 5, '0'),
    (mod(g, 5) + 1),                                       -- cycle through 5 programmes
    CASE WHEN mod(g, 2) = 0 THEN                           -- male first names
        (ARRAY[
            'Akpan','Ntiedo','Ekemini','Inyang','Uduak','Ndifreke','Edidiong','Ubong','Aniekan','Etim',
            'Emmanuel','Daniel','Joseph','Samuel','David','Mark','Paul','Victor','John','Peter'
        ])[mod(g, 20) + 1]
    ELSE                                                   -- female first names
        (ARRAY[
            'Emem','Ekaette','Ima','Abasi','Ese','Mfon','Nse','Affiong','Edidiong','Eno',
            'Iniobong','Iquo','Uduak','Comfort','Grace','Mary','Sarah','Esther','Rita','Patience'
        ])[mod(g, 20) + 1]
    END,
    (ARRAY[
        'Ntah','Edet','Akpan','Inyang','Udoh','Ekanem','Bassey','Okon','Effiong','Umoh',
        'Asuquo','Eshiet','Nkanta','Udoudo','James','Peter','Samuel','David','Joseph','Mark'
    ])[mod(g, 20) + 1],
    CASE WHEN mod(g, 2) = 0 THEN 'M' ELSE 'F' END,
    CASE mod(g, 4)
        WHEN 0 THEN 400 WHEN 1 THEN 300 WHEN 2 THEN 200 ELSE 100
    END,
    CASE WHEN mod(g, 25) = 0 THEN 'suspended' ELSE 'active' END,
    CASE mod(g, 4)
        WHEN 0 THEN '2021/2022'
        WHEN 1 THEN '2022/2023'
        WHEN 2 THEN '2023/2024'
        ELSE '2024/2025'
    END,
    (ARRAY[
        'Akwa Ibom','Rivers','Cross River','Abia','Imo','Ebonyi','Lagos','Delta','Bayelsa','Edo'
    ])[mod(g, 10) + 1],
    250000 + mod(g, 4) * 50000                            -- tuition ₦250k - ₦400k
FROM generate_series(100, 2099) g
ON CONFLICT (matric_no) DO NOTHING;

-- =====================================================================
-- 2. Result batches for every (course, semester) combination that does
-- not already have one. Past semesters -> PUBLISHED; current semester
-- (2024/2025 SECOND) -> PENDING. Each batch is owned by the course's
-- department and taught by the first lecturer in that department.
-- =====================================================================
INSERT INTO result_batch (course_id, semester_id, dept_id, lecturer_id, status, published_at)
SELECT
    c.course_id,
    sem.semester_id,
    c.dept_id,
    (SELECT lecturer_id FROM lecturer l
       WHERE l.dept_id = c.dept_id
       ORDER BY lecturer_id LIMIT 1),
    CASE
        WHEN sem.session = '2024/2025' AND sem.term = 'SECOND' THEN 'PENDING'
        ELSE 'PUBLISHED'
    END,
    CASE
        WHEN sem.session = '2024/2025' AND sem.term = 'SECOND' THEN NULL
        ELSE CURRENT_TIMESTAMP - INTERVAL '3 months'
    END
FROM course c
CROSS JOIN semester sem
WHERE sem.session IN ('2023/2024', '2024/2025')
  AND sem.term   IN ('FIRST', 'SECOND')
  AND NOT EXISTS (
        SELECT 1 FROM result_batch rb
        WHERE rb.course_id   = c.course_id
          AND rb.semester_id = sem.semester_id
          AND rb.dept_id     = c.dept_id
  )
ON CONFLICT (course_id, semester_id, dept_id) DO NOTHING;

-- =====================================================================
-- 3. Bulk assessment_result (~60,000 rows).
-- Strategy: for each result row g in 1..60000, pick a batch by
-- (g mod n_batches) and a student by (g div n_batches). This guarantees
-- one student appears at most once per batch -> the partial UNIQUE index
-- one_active_result_per_student_course_semester is never violated.
-- Past-semester (PUBLISHED) batches get PUBLISHED results; the current
-- semester gets a mix of APPROVED / PENDING / DRAFT.
-- =====================================================================
WITH
batches AS (
    SELECT batch_id, course_id, semester_id, status,
           ROW_NUMBER() OVER (ORDER BY batch_id)         AS batch_rn,
           COUNT(*)       OVER ()                        AS n_batches
    FROM result_batch
),
students AS (
    SELECT matric_no,
           ROW_NUMBER() OVER (ORDER BY matric_no)        AS student_rn,
           COUNT(*)      OVER ()                         AS n_students
    FROM student
),
-- n_batches is constant in every row of `batches`; pull it out once
bcount AS (SELECT n_batches FROM batches LIMIT 1),
scount AS (SELECT n_students FROM students LIMIT 1)
INSERT INTO assessment_result
    (batch_id, matric_no, course_id, semester_id,
     ca_score, exam_score, status, superseded)
SELECT
    b.batch_id,
    s.matric_no,
    b.course_id,
    b.semester_id,
    -- CA in 8..38 (so the total spans most grade bands)
    (random() * 30 + 8)::numeric(5,2),
    -- Exam in 5..55
    (random() * 50 + 5)::numeric(5,2),
    CASE
        WHEN b.status = 'PUBLISHED' THEN 'APPROVED'   -- a published batch holds only APPROVED results
        WHEN mod(g, 10) < 3 THEN 'DRAFT'         -- 30% DRAFT
        WHEN mod(g, 10) < 6 THEN 'PENDING'      -- 30% PENDING
        ELSE                       'APPROVED'    -- 40% APPROVED
    END,
    FALSE
FROM generate_series(1, 60000) AS g(g)
JOIN bcount bc ON TRUE
JOIN scount sc ON TRUE
JOIN batches  b ON b.batch_rn  = mod(g - 1, bc.n_batches) + 1
JOIN students s ON s.student_rn = (g - 1) / bc.n_batches + 1
-- Stay inside the number of students we actually have.
WHERE (g - 1) / bc.n_batches + 1 <= sc.n_students
ON CONFLICT DO NOTHING;

-- =====================================================================
-- 4. A carry-over / resit example: ICU/2024/00004 failed CSC101 in
-- 2023/2024 first (the F-grade row seeded earlier). They re-take it in
-- 2024/2025 first semester and pass. The resit row is a NEW (matric,
-- course, semester) tuple -- different semester_id, so no partial UNIQUE
-- conflict and no need to supersede the old row. The old F stays as the
-- historical record (it is in a PUBLISHED batch and cannot be modified
-- without an audit row in the same transaction, which is the correct
-- behaviour).
-- =====================================================================
INSERT INTO assessment_result (matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
SELECT
    st.matric_no, c.course_id, sem.semester_id,
    32.00, 48.00, 'APPROVED', FALSE
FROM student st
JOIN course c ON c.code = 'CSC101'
JOIN semester sem ON sem.session = '2024/2025' AND sem.term = 'FIRST'
WHERE st.matric_no = 'ICU/2024/00004'
  AND NOT EXISTS (
        SELECT 1 FROM assessment_result ar
        WHERE ar.matric_no = st.matric_no
          AND ar.course_id = c.course_id
          AND ar.semester_id = sem.semester_id
          AND ar.superseded = FALSE
  )
ON CONFLICT DO NOTHING;

-- =====================================================================
-- 4b. Demonstrate the supersede mechanism with a SEPARATE non-published
-- row, so the publication-block trigger does not fire. Take a DRAFT
-- result in the current (PENDING) semester, insert an audit row in the
-- same transaction, then mark the old DRAFT row superseded and replace
-- it with a corrected APPROVED row.
-- =====================================================================
DO $$
DECLARE
    v_old_id   BIGINT;
    v_matric   VARCHAR := 'ICU/2024/00100';
    v_course   INT;
    v_sem      INT;
BEGIN
    SELECT course_id INTO v_course FROM course WHERE code = 'CSC202';
    SELECT semester_id INTO v_sem
      FROM semester WHERE session = '2024/2025' AND term = 'SECOND';

    -- find a DRAFT row to supersede
    SELECT ar.result_id INTO v_old_id
    FROM assessment_result ar
    WHERE ar.matric_no = v_matric
      AND ar.course_id = v_course
      AND ar.semester_id = v_sem
      AND ar.status = 'DRAFT'
      AND ar.superseded = FALSE
    LIMIT 1;

    IF v_old_id IS NULL THEN
        RAISE NOTICE 'No DRAFT row found for the supersede demo -- skipped.';
        RETURN;
    END IF;

    -- Insert the audit row FIRST in this transaction.
    INSERT INTO grade_change_audit
        (result_id, changed_by, reason, old_total_score, new_total_score, old_grade, new_grade)
    VALUES
        (v_old_id, 'Exam Officer', 'Superseded by re-marked APPROVED row',
         NULL, NULL, NULL, NULL);

    -- Now mark the old row superseded (the publication-block trigger
    -- sees the audit row in this transaction and allows the change).
    UPDATE assessment_result SET superseded = TRUE WHERE result_id = v_old_id;

    -- Insert the replacement APPROVED row.
    INSERT INTO assessment_result
        (matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
    VALUES (v_matric, v_course, v_sem, 28.00, 45.00, 'APPROVED', FALSE)
    ON CONFLICT DO NOTHING;
END $$;

-- =====================================================================
-- 5. CGPA self-check: recompute CGPA from the raw result rows for every
-- student that has any results, and compare with the v_cgpa_summary view.
-- Expected: 0 mismatches.
-- =====================================================================
WITH recomputed AS (
    SELECT
        ar.matric_no,
        CASE WHEN SUM(c.credit_units) > 0
             THEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units)
             ELSE NULL END AS cgpa_raw
    FROM assessment_result ar
    JOIN course c ON c.course_id = ar.course_id
    WHERE ar.status IN ('APPROVED', 'PUBLISHED')
      AND ar.superseded = FALSE
    GROUP BY ar.matric_no
)
SELECT
    count(*)                                               AS students_with_results,
    count(*) FILTER (WHERE abs(r.cgpa_raw - v.cgpa) > 0.001) AS cgpa_mismatches
FROM recomputed r
JOIN v_cgpa_summary v ON v.matric_no = r.matric_no;

-- =====================================================================
-- 6. Distribution of result statuses (sanity, and shows that the current
-- semester still has PENDING / DRAFT rows for the demos).
-- =====================================================================
SELECT
    sem.session, sem.term,
    ar.status,
    count(*) AS n
FROM assessment_result ar
JOIN semester sem ON sem.semester_id = ar.semester_id
GROUP BY sem.session, sem.term, ar.status
ORDER BY sem.session, sem.term, ar.status;

-- =====================================================================
-- 7. Final count of the biggest table.
-- =====================================================================
SELECT 'assessment_result total' AS table_name, count(*) AS n FROM assessment_result;
