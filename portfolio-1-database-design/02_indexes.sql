-- 02_indexes.sql
-- Purpose: Create B-tree indexes on every foreign key and on every column
-- that a trigger or a report uses. Includes a few partial indexes for the
-- GPA views. Idempotent (CREATE INDEX IF NOT EXISTS).
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 02_indexes.sql

SET timezone TO 'Africa/Lagos';

-- ---------------------------------------------------------------------
-- FK indexes (every FK column gets an index)
-- ---------------------------------------------------------------------

-- department -> faculty
CREATE INDEX IF NOT EXISTS idx_department_faculty_id
    ON department (faculty_id);

-- programme -> department
CREATE INDEX IF NOT EXISTS idx_programme_dept_id
    ON programme (dept_id);

-- lecturer -> department
CREATE INDEX IF NOT EXISTS idx_lecturer_dept_id
    ON lecturer (dept_id);

-- course -> department
CREATE INDEX IF NOT EXISTS idx_course_dept_id
    ON course (dept_id);

-- student -> programme
CREATE INDEX IF NOT EXISTS idx_student_programme_id
    ON student (programme_id);

-- result_batch FKs
CREATE INDEX IF NOT EXISTS idx_result_batch_course_id
    ON result_batch (course_id);
CREATE INDEX IF NOT EXISTS idx_result_batch_semester_id
    ON result_batch (semester_id);
CREATE INDEX IF NOT EXISTS idx_result_batch_dept_id
    ON result_batch (dept_id);
CREATE INDEX IF NOT EXISTS idx_result_batch_lecturer_id
    ON result_batch (lecturer_id);

-- assessment_result FKs (batch_id, matric_no, course_id, semester_id)
-- matric_no is also the leading column of the partial unique index, but
-- that index has a WHERE clause so it cannot serve queries that do not
-- filter on superseded = FALSE; add a plain index too.
CREATE INDEX IF NOT EXISTS idx_assessment_result_batch_id
    ON assessment_result (batch_id);
CREATE INDEX IF NOT EXISTS idx_assessment_result_matric_no
    ON assessment_result (matric_no);
CREATE INDEX IF NOT EXISTS idx_assessment_result_course_id
    ON assessment_result (course_id);
CREATE INDEX IF NOT EXISTS idx_assessment_result_semester_id
    ON assessment_result (semester_id);

-- grade_change_audit -> assessment_result
CREATE INDEX IF NOT EXISTS idx_grade_change_audit_result_id
    ON grade_change_audit (result_id);

-- ---------------------------------------------------------------------
-- Indexes used by triggers / reports
-- ---------------------------------------------------------------------

-- trg_check_batch_publish reads assessment_result by (batch_id, status)
CREATE INDEX IF NOT EXISTS idx_assessment_result_batch_status
    ON assessment_result (batch_id, status);

-- trg_block_change_after_publication reads result_batch by batch_id (PK already)
-- and grade_change_audit by (result_id, created_at)
CREATE INDEX IF NOT EXISTS idx_grade_change_audit_result_created
    ON grade_change_audit (result_id, created_at);

-- GPA views filter on (status, superseded); partial index helps
CREATE INDEX IF NOT EXISTS idx_assessment_result_active_status
    ON assessment_result (matric_no)
    WHERE superseded = FALSE AND status IN ('APPROVED', 'PUBLISHED');

-- "last 30 days of changes" report (Q4 in portfolio-2)
CREATE INDEX IF NOT EXISTS idx_grade_change_audit_created_at
    ON grade_change_audit (created_at);
CREATE INDEX IF NOT EXISTS idx_assessment_result_updated_at
    ON assessment_result (updated_at);

-- A lecturer's courses report (Q3 in portfolio-2): join result_batch to lecturer
-- by staff_no. lecturer.email / staff_no already UNIQUE so they are indexed.

-- result sheet query (Q2) filters result_batch by batch_id (PK) then joins to
-- assessment_result by batch_id (covered above).

-- transcript query (Q1) filters assessment_result by matric_no (covered above)
-- plus a condition on status / superseded.

-- ---------------------------------------------------------------------
-- Summary (for the README)
-- ---------------------------------------------------------------------
SELECT 'indexes created' AS note,
       count(*) AS total_indexes
FROM pg_indexes
WHERE schemaname = 'public' AND tablename IN
      ('faculty','department','programme','lecturer','course','grading_scale',
       'student','semester','result_batch','assessment_result','grade_change_audit');
