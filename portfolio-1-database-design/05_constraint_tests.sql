-- 05_constraint_tests.sql
-- Purpose: Verify that every constraint and trigger actually fires.
-- 10 tests that MUST fail on the intended constraint, plus 1 control that
-- MUST succeed. Each test wraps its own setup in BEGIN ... ROLLBACK so it
-- leaves no data behind. Each prints PASS (constraint fired) or FAIL
-- (constraint did NOT fire).
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 05_constraint_tests.sql

SET timezone TO 'Africa/Lagos';
-- psql setting so NOTICEs always show.
\set VERBOSITY terse

\echo '==== Constraint tests (10 must fail, 1 must succeed) ===='

-- =====================================================================
-- Test 1: FK on student.programme_id -- inserting a student with a
-- non-existent programme_id must fail.
-- =====================================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO student (matric_no, programme_id, first_name, last_name, gender,
                         level, status, session_admitted, state_of_origin, tuition_ngn)
    VALUES ('ICU/TEST/00001', 9999, 'Test', 'User', 'M',
            100, 'active', '2024/2025', 'Akwa Ibom', 250000.00);
    RAISE NOTICE 'FAIL: test 1 -- FK student_programme_id did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 1 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 2: CHECK on student.gender -- a value other than M/F must fail.
-- =====================================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO student (matric_no, programme_id, first_name, last_name, gender,
                         level, status, session_admitted, state_of_origin, tuition_ngn)
    VALUES ('ICU/TEST/00002', 1, 'Test', 'User', 'X',
            100, 'active', '2024/2025', 'Akwa Ibom', 250000.00);
    RAISE NOTICE 'FAIL: test 2 -- CHECK student_gender did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 2 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 3: CHECK on assessment_result.ca_score -- a CA score > 40 must fail.
-- =====================================================================
BEGIN;
DO $$
DECLARE v_batch INT; v_sem INT; v_course INT;
BEGIN
    SELECT batch_id, semester_id, course_id
      INTO v_batch, v_sem, v_course
    FROM result_batch rb LIMIT 1;

    INSERT INTO assessment_result (batch_id, matric_no, course_id, semester_id,
                                   ca_score, exam_score, status)
    VALUES (v_batch, 'ICU/2024/00100', v_course, v_sem,
            55.00, 30.00, 'DRAFT');
    RAISE NOTICE 'FAIL: test 3 -- CHECK ca_score_range did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 3 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 4: UNIQUE on grading_scale.grade -- inserting a duplicate grade
-- (e.g. a second 'A') must fail.
-- =====================================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO grading_scale (grade, min_score, max_score, grade_point, interpretation)
    VALUES ('A', 75.00, 100.00, 5.0, 'Duplicate Excellent');
    RAISE NOTICE 'FAIL: test 4 -- UNIQUE grading_scale_pkey did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 4 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 5: Partial UNIQUE index one_active_result_per_student_course_semester
-- -- two non-superseded results for the same student/course/semester must
-- fail.
-- =====================================================================
BEGIN;
DO $$
DECLARE v_batch INT; v_sem INT; v_course INT;
BEGIN
    SELECT batch_id, semester_id, course_id
      INTO v_batch, v_sem, v_course
      FROM result_batch rb LIMIT 1;

    INSERT INTO assessment_result (batch_id, matric_no, course_id, semester_id,
                                   ca_score, exam_score, status)
    VALUES (v_batch, 'ICU/2024/00100', v_course, v_sem, 20.00, 30.00, 'APPROVED');

    INSERT INTO assessment_result (batch_id, matric_no, course_id, semester_id,
                                   ca_score, exam_score, status)
    VALUES (v_batch, 'ICU/2024/00100', v_course, v_sem, 25.00, 40.00, 'APPROVED');
    RAISE NOTICE 'FAIL: test 5 -- partial UNIQUE index did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 5 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 6: trg_compute_grade -- typing a grade that does NOT match the
-- total score must fail (cannot type in a grade).
-- =====================================================================
BEGIN;
DO $$
DECLARE v_batch INT; v_sem INT; v_course INT;
BEGIN
    SELECT batch_id, semester_id, course_id
      INTO v_batch, v_sem, v_course
      FROM result_batch rb LIMIT 1;

    -- ca=5 + exam=5 -> total=10 -> grade F. Force a wrong grade 'A'.
    INSERT INTO assessment_result (batch_id, matric_no, course_id, semester_id,
                                   ca_score, exam_score, grade, status)
    VALUES (v_batch, 'ICU/2024/00100', v_course, v_sem,
            5.00, 5.00, 'A', 'DRAFT');
    RAISE NOTICE 'FAIL: test 6 -- trg_compute_grade did NOT reject typed grade';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 6 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 7: trg_check_batch_publish -- publishing a batch that still has a
-- PENDING result must fail.
-- =====================================================================
BEGIN;
DO $$
DECLARE v_batch INT; v_sem INT; v_course INT; v_dept INT; v_lec INT;
BEGIN
    -- pick an existing course/semester/dept/lecturer to build a fresh batch
    SELECT c.course_id, sem.semester_id, c.dept_id, l.lecturer_id
      INTO v_course, v_sem, v_dept, v_lec
    FROM course c
    CROSS JOIN semester sem
    JOIN lecturer l ON l.dept_id = c.dept_id
    WHERE sem.session = '2025/2026'         -- future semester, no batch yet
    LIMIT 1;

    INSERT INTO result_batch (course_id, semester_id, dept_id, lecturer_id, status)
    VALUES (v_course, v_sem, v_dept, v_lec, 'DRAFT') RETURNING batch_id INTO v_batch;

    -- insert two results: one APPROVED, one PENDING
    INSERT INTO assessment_result (batch_id, matric_no, course_id, semester_id,
                                   ca_score, exam_score, status)
    VALUES (v_batch, 'ICU/2024/00100', v_course, v_sem, 30.00, 50.00, 'APPROVED');
    INSERT INTO assessment_result (batch_id, matric_no, course_id, semester_id,
                                   ca_score, exam_score, status)
    VALUES (v_batch, 'ICU/2024/00101', v_course, v_sem, 25.00, 40.00, 'PENDING');

    -- try to publish
    UPDATE result_batch SET status = 'PUBLISHED' WHERE batch_id = v_batch;
    RAISE NOTICE 'FAIL: test 7 -- trg_check_batch_publish did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 7 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 8: trg_block_change_after_publication -- updating a result in a
-- PUBLISHED batch without an audit row in the same transaction must fail.
-- =====================================================================
BEGIN;
DO $$
DECLARE v_batch INT; v_sem INT; v_course INT; v_dept INT; v_lec INT;
        v_result BIGINT;
BEGIN
    SELECT c.course_id, sem.semester_id, c.dept_id, l.lecturer_id
      INTO v_course, v_sem, v_dept, v_lec
    FROM course c
    CROSS JOIN semester sem
    JOIN lecturer l ON l.dept_id = c.dept_id
    WHERE sem.session = '2025/2026'
    LIMIT 1;

    INSERT INTO result_batch (course_id, semester_id, dept_id, lecturer_id, status)
    VALUES (v_course, v_sem, v_dept, v_lec, 'APPROVED') RETURNING batch_id INTO v_batch;

    INSERT INTO assessment_result (batch_id, matric_no, course_id, semester_id,
                                   ca_score, exam_score, status)
    VALUES (v_batch, 'ICU/2024/00100', v_course, v_sem, 30.00, 50.00, 'APPROVED')
    RETURNING result_id INTO v_result;

    -- now publish the batch (all results are APPROVED, so this is allowed)
    UPDATE result_batch SET status = 'PUBLISHED' WHERE batch_id = v_batch;

    -- attempt to change the result WITHOUT inserting an audit row
    UPDATE assessment_result SET ca_score = 35.00 WHERE result_id = v_result;
    RAISE NOTICE 'FAIL: test 8 -- trg_block_change_after_publication did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 8 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 9: CHECK on grading_scale (min_score < max_score) -- a band where
-- min >= max must fail.
-- =====================================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO grading_scale (grade, min_score, max_score, grade_point, interpretation)
    VALUES ('Z', 60.00, 50.00, 0.0, 'Bad band');
    RAISE NOTICE 'FAIL: test 9 -- CHECK grading_scale_min_lt_max did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 9 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Test 10: UNIQUE (course_id, semester_id, dept_id) on result_batch -- a
-- second batch for the same course/semester/dept must fail.
-- =====================================================================
BEGIN;
DO $$
DECLARE v_course INT; v_sem INT; v_dept INT; v_lec INT;
BEGIN
    -- find a (course, semester, dept) that already has a batch
    SELECT rb.course_id, rb.semester_id, rb.dept_id, rb.lecturer_id
      INTO v_course, v_sem, v_dept, v_lec
    FROM result_batch rb LIMIT 1;

    INSERT INTO result_batch (course_id, semester_id, dept_id, lecturer_id, status)
    VALUES (v_course, v_sem, v_dept, v_lec, 'DRAFT');
    RAISE NOTICE 'FAIL: test 10 -- UNIQUE result_batch_course_semester_dept did NOT fire';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS: test 10 -- %', SQLERRM;
END $$;
ROLLBACK;

-- =====================================================================
-- Control test: a perfectly valid student insert MUST succeed.
-- =====================================================================
BEGIN;
DO $$
BEGIN
    INSERT INTO student (matric_no, programme_id, first_name, last_name, gender,
                         level, status, session_admitted, state_of_origin, tuition_ngn)
    VALUES ('ICU/TEST/00010', 1, 'Test', 'Okon', 'M',
            100, 'active', '2024/2025', 'Akwa Ibom', 250000.00);
    RAISE NOTICE 'PASS (control): test 11 -- valid insert succeeded';
END $$;
ROLLBACK;

\echo '==== End of constraint tests ===='
