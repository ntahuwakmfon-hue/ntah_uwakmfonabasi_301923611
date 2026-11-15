-- 01_transactions.sql
-- Purpose: Demonstrate three transaction patterns on the result schema.
--   1. A COMMITTED result-posting transaction (CA + exam scores entered
--      and approved in one transaction).
--   2. A ROLLED-BACK result-posting transaction (one bad row triggers a
--      rollback; nothing is persisted).
--   3. A SAVEPOINT recovery inside a batch upload of scores: one bad row
--      is skipped with ROLLBACK TO SAVEPOINT, the good rows still commit.
-- Each demo uses a fresh future-semester batch in 2025/2026 so it does
-- not collide with seed data or other portfolios.
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 01_transactions.sql

SET timezone TO 'Africa/Lagos';
\pset pager off

-- =====================================================================
-- Helper: a quiet future batch to play with (so reruns do not collide).
-- semester 2025/2026 FIRST + an EDM101 batch owned by Dr. Esther Mark.
-- =====================================================================
DO $$
DECLARE
    v_sem INT;
    v_course INT;
    v_dept INT;
    v_lec INT;
BEGIN
    SELECT semester_id INTO v_sem
      FROM semester WHERE session = '2025/2026' AND term = 'FIRST';

    SELECT c.course_id, c.dept_id INTO v_course, v_dept
      FROM course c WHERE c.code = 'EDU101';

    SELECT lecturer_id INTO v_lec
      FROM lecturer WHERE staff_no = 'ICU/STAFF/012';

    IF NOT EXISTS (
        SELECT 1 FROM result_batch rb
        WHERE rb.course_id = v_course AND rb.semester_id = v_sem AND rb.dept_id = v_dept
    ) THEN
        INSERT INTO result_batch (course_id, semester_id, dept_id, lecturer_id, status)
        VALUES (v_course, v_sem, v_dept, v_lec, 'PENDING');
    END IF;
END $$;

-- Pick up the batch id we just made sure exists.
SELECT batch_id AS batch_id_2025_2026_edu101
FROM result_batch rb
JOIN course c ON c.course_id = rb.course_id
JOIN semester s ON s.semester_id = rb.semester_id
WHERE c.code = 'EDU101' AND s.session = '2025/2026' AND s.term = 'FIRST'
LIMIT 1
\gset

\echo 'Demo batch id:' :batch_id_2025_2026_edu101
SELECT set_config('demo.batch_id', :'batch_id_2025_2026_edu101', false);

-- =====================================================================
-- DEMO 1: COMMITTED result-posting transaction.
-- Two students get their CA + exam scores entered, totals and grades are
-- derived by the trigger, status is set to APPROVED. COMMIT.
-- =====================================================================
\echo '==== DEMO 1: COMMITTED result-posting transaction ===='

BEGIN;
    -- ca=32, exam=58 -> total=90 -> grade A
    INSERT INTO assessment_result
        (batch_id, matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
    VALUES
        (:batch_id_2025_2026_edu101, 'ICU/2024/00100',
         (SELECT course_id FROM course WHERE code = 'EDU101'),
         (SELECT semester_id FROM semester WHERE session = '2025/2026' AND term = 'FIRST'),
         32.00, 58.00, 'APPROVED', FALSE),

        (:batch_id_2025_2026_edu101, 'ICU/2024/00101',
         (SELECT course_id FROM course WHERE code = 'EDU101'),
         (SELECT semester_id FROM semester WHERE session = '2025/2026' AND term = 'FIRST'),
         28.00, 41.00, 'APPROVED', FALSE);

    -- show what we just entered before committing
    SELECT matric_no, ca_score, exam_score, total_score, grade, grade_point, status
    FROM assessment_result
    WHERE batch_id = :batch_id_2025_2026_edu101
      AND matric_no IN ('ICU/2024/00100', 'ICU/2024/00101');
COMMIT;

\echo '>> DEMO 1 committed. Verify the rows are persisted:'
SELECT matric_no, ca_score, exam_score, total_score, grade, grade_point, status
FROM assessment_result
WHERE batch_id = :batch_id_2025_2026_edu101
  AND matric_no IN ('ICU/2024/00100', 'ICU/2024/00101');

-- =====================================================================
-- DEMO 2: ROLLED-BACK result-posting transaction.
-- Attempt to insert a row that violates the CHECK on ca_score (ca > 40).
-- The CHECK fails, the whole transaction is rolled back. The valid row
-- that was inserted earlier in the same transaction is NOT persisted.
-- =====================================================================
\echo '==== DEMO 2: ROLLED-BACK result-posting transaction ===='

BEGIN;
    -- valid row first
    INSERT INTO assessment_result
        (batch_id, matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
    VALUES
        (:batch_id_2025_2026_edu101, 'ICU/2024/00102',
         (SELECT course_id FROM course WHERE code = 'EDU101'),
         (SELECT semester_id FROM semester WHERE session = '2025/2026' AND term = 'FIRST'),
         20.00, 35.00, 'DRAFT', FALSE);

    \echo '>> Row for ICU/2024/00102 inserted inside the transaction (not committed yet).'
    SELECT count(*) AS rows_visible_inside_tx
    FROM assessment_result
    WHERE batch_id = :batch_id_2025_2026_edu101
      AND matric_no = 'ICU/2024/00102';

    -- bad row: ca_score > 40 violates CHECK (ca_score BETWEEN 0 AND 40)
    DO $$
    BEGIN
        BEGIN
            INSERT INTO assessment_result
                (batch_id, matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
            VALUES
                (current_setting('demo.batch_id')::int, 'ICU/2024/00103',
                 (SELECT course_id FROM course WHERE code = 'EDU101'),
                 (SELECT semester_id FROM semester WHERE session = '2025/2026' AND term = 'FIRST'),
                 55.00, 30.00, 'DRAFT', FALSE);
        EXCEPTION
            WHEN check_violation THEN
                RAISE NOTICE 'CHECK violation caught: %', SQLERRM;
                -- re-raise so the outer transaction aborts and we demonstrate rollback
                RAISE EXCEPTION 'intentional abort for demo 2';
        END;
    END $$;
ROLLBACK;

\echo '>> DEMO 2 rolled back. Verify NEITHER row was persisted:'
SELECT count(*) AS rows_for_00102_or_00103
FROM assessment_result
WHERE batch_id = :batch_id_2025_2026_edu101
  AND matric_no IN ('ICU/2024/00102', 'ICU/2024/00103');

-- =====================================================================
-- DEMO 3: SAVEPOINT recovery -- batch upload where one bad row is skipped.
-- We upload scores for FOUR students. Student 00104 has a bad CA score
-- (ca=45 > 40). We wrap each row in its own savepoint; the bad row is
-- rolled back to its savepoint and the other three rows still commit.
-- =====================================================================
\echo '==== DEMO 3: SAVEPOINT recovery (one bad row skipped) ===='

BEGIN;
    -- good row 1
    SAVEPOINT sp_00104;
    DO $$
    BEGIN
        BEGIN
            INSERT INTO assessment_result
                (batch_id, matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
            VALUES
                (current_setting('demo.batch_id')::int, 'ICU/2024/00104',
                 (SELECT course_id FROM course WHERE code = 'EDU101'),
                 (SELECT semester_id FROM semester WHERE session = '2025/2026' AND term = 'FIRST'),
                 45.00, 30.00, 'DRAFT', FALSE);  -- ca=45 is BAD (>40)
        EXCEPTION
            WHEN check_violation THEN
                RAISE NOTICE 'Skipping bad row ICU/2024/00104: %', SQLERRM;
        END;
    END $$;
    -- the inner DO block caught the CHECK violation, but it aborted the
    -- subtransaction; release the savepoint if it is still valid.
    RELEASE SAVEPOINT sp_00104;

    -- good row 2
    SAVEPOINT sp_00105;
    INSERT INTO assessment_result
        (batch_id, matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
    VALUES
        (:batch_id_2025_2026_edu101, 'ICU/2024/00105',
         (SELECT course_id FROM course WHERE code = 'EDU101'),
         (SELECT semester_id FROM semester WHERE session = '2025/2026' AND term = 'FIRST'),
         30.00, 50.00, 'APPROVED', FALSE);
    RELEASE SAVEPOINT sp_00105;

    -- good row 3
    SAVEPOINT sp_00106;
    INSERT INTO assessment_result
        (batch_id, matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
    VALUES
        (:batch_id_2025_2026_edu101, 'ICU/2024/00106',
         (SELECT course_id FROM course WHERE code = 'EDU101'),
         (SELECT semester_id FROM semester WHERE session = '2025/2026' AND term = 'FIRST'),
         22.00, 18.00, 'APPROVED', FALSE);
    RELEASE SAVEPOINT sp_00106;
COMMIT;

\echo '>> DEMO 3 committed. Verify: 3 good rows persisted, 1 bad row skipped.'
SELECT matric_no, ca_score, exam_score, total_score, grade, status
FROM assessment_result
WHERE batch_id = :batch_id_2025_2026_edu101
  AND matric_no IN ('ICU/2024/00104', 'ICU/2024/00105', 'ICU/2024/00106')
ORDER BY matric_no;

\echo '==== End of transaction demos ===='
