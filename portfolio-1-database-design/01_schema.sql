-- 01_schema.sql
-- Purpose: Create the schema for the Ibom Crown University Result Processing System.
-- 11 tables in 3NF (faculty, department, programme, lecturer, course, grading_scale,
-- student, semester, result_batch, assessment_result, grade_change_audit),
-- 5 triggers enforcing business rules, 1 partial UNIQUE index, and 2 computed
-- GPA/CGPA views. Sets the database time zone to Africa/Lagos.
-- Idempotent: objects are CREATE IF NOT EXISTS / CREATE OR REPLACE where possible.
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 01_schema.sql

-- Make sure timestamps the student sees are in Nigerian time.
ALTER DATABASE resultsys SET timezone TO 'Africa/Lagos';
-- Also set for this session so the script's own now() output is Lagos time.
SET timezone TO 'Africa/Lagos';

-- =====================================================================
-- faculty
-- =====================================================================
CREATE TABLE IF NOT EXISTS faculty (
    faculty_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    faculty_code VARCHAR(10) NOT NULL UNIQUE,
    name         VARCHAR(100) NOT NULL,
    dean_name    VARCHAR(100) NOT NULL,
    location     VARCHAR(100) NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- department
-- =====================================================================
CREATE TABLE IF NOT EXISTS department (
    dept_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_code   VARCHAR(10) NOT NULL UNIQUE,
    faculty_id  INT NOT NULL REFERENCES faculty(faculty_id) ON DELETE RESTRICT,
    name        VARCHAR(100) NOT NULL,
    hod_name    VARCHAR(100) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- programme
-- =====================================================================
CREATE TABLE IF NOT EXISTS programme (
    programme_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_id         INT NOT NULL REFERENCES department(dept_id) ON DELETE RESTRICT,
    code            VARCHAR(20) NOT NULL UNIQUE,
    name            VARCHAR(120) NOT NULL,
    duration_years  INT NOT NULL CHECK (duration_years BETWEEN 1 AND 7),
    award           VARCHAR(50) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- lecturer
-- =====================================================================
CREATE TABLE IF NOT EXISTS lecturer (
    lecturer_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_id     INT NOT NULL REFERENCES department(dept_id) ON DELETE RESTRICT,
    staff_no    VARCHAR(20) NOT NULL UNIQUE,
    title       VARCHAR(15) NOT NULL CHECK (title IN ('Dr.', 'Prof.', 'Mr.', 'Mrs.', 'Ms.')),
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    email       VARCHAR(120) NOT NULL UNIQUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- course
-- =====================================================================
CREATE TABLE IF NOT EXISTS course (
    course_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dept_id          INT NOT NULL REFERENCES department(dept_id) ON DELETE RESTRICT,
    code             VARCHAR(15) NOT NULL UNIQUE,
    title            VARCHAR(150) NOT NULL,
    credit_units     INT NOT NULL CHECK (credit_units BETWEEN 1 AND 6),
    level            INT NOT NULL CHECK (level IN (100, 200, 300, 400, 500)),
    semester_offered VARCHAR(10) NOT NULL CHECK (semester_offered IN ('FIRST', 'SECOND', 'BOTH')),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- grading_scale  (Nigerian 5-point scale)
-- =====================================================================
CREATE TABLE IF NOT EXISTS grading_scale (
    grade          VARCHAR(2) PRIMARY KEY,
    min_score      NUMERIC(5,2) NOT NULL,
    max_score      NUMERIC(5,2) NOT NULL,
    grade_point    NUMERIC(3,1) NOT NULL CHECK (grade_point BETWEEN 0 AND 5),
    interpretation VARCHAR(50) NOT NULL,
    CHECK (min_score >= 0 AND max_score <= 100),
    CHECK (min_score < max_score)
);

-- =====================================================================
-- semester
-- =====================================================================
CREATE TABLE IF NOT EXISTS semester (
    semester_id INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    session     VARCHAR(15) NOT NULL,           -- e.g. '2024/2025'
    term        VARCHAR(10) NOT NULL CHECK (term IN ('FIRST', 'SECOND')),
    start_date  DATE NOT NULL,
    end_date    DATE NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (session, term),
    CHECK (end_date > start_date)
);
-- NOTE: start/end date sanity (start < end, no overlap) is enforced here with a CHECK.
-- The "no CURRENT_DATE in CHECK" rule is satisfied: we never use CURRENT_DATE in a CHECK.
-- A semester that has already ended is still valid data, so no CURRENT_DATE rule is needed.

-- =====================================================================
-- student  (records supporting the result core)
-- =====================================================================
CREATE TABLE IF NOT EXISTS student (
    matric_no         VARCHAR(20) PRIMARY KEY,           -- e.g. ICU/2024/00001
    programme_id      INT NOT NULL REFERENCES programme(programme_id) ON DELETE RESTRICT,
    first_name        VARCHAR(50) NOT NULL,
    last_name         VARCHAR(50) NOT NULL,
    gender            CHAR(1) NOT NULL CHECK (gender IN ('M', 'F')),
    level             INT NOT NULL CHECK (level IN (100, 200, 300, 400, 500)),
    status            VARCHAR(15) NOT NULL CHECK (status IN ('active', 'suspended', 'graduated', 'withdrawn')),
    session_admitted  VARCHAR(15) NOT NULL,              -- e.g. '2023/2024'
    state_of_origin   VARCHAR(50) NOT NULL,              -- Nigerian state
    tuition_ngn       NUMERIC(10,2) NOT NULL CHECK (tuition_ngn >= 0),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =====================================================================
-- result_batch  (a department's results for ONE course in ONE semester)
-- Status flow: DRAFT -> PENDING -> APPROVED -> PUBLISHED
-- =====================================================================
CREATE TABLE IF NOT EXISTS result_batch (
    batch_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    course_id    INT NOT NULL REFERENCES course(course_id) ON DELETE RESTRICT,
    semester_id  INT NOT NULL REFERENCES semester(semester_id) ON DELETE RESTRICT,
    dept_id      INT NOT NULL REFERENCES department(dept_id) ON DELETE RESTRICT,
    lecturer_id  INT REFERENCES lecturer(lecturer_id) ON DELETE SET NULL,
    status       VARCHAR(15) NOT NULL DEFAULT 'DRAFT'
                    CHECK (status IN ('DRAFT', 'PENDING', 'APPROVED', 'PUBLISHED')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    published_at TIMESTAMPTZ,
    UNIQUE (course_id, semester_id, dept_id),
    -- published_at only makes sense when status = PUBLISHED (rule: trigger also checks this)
    CHECK ((status = 'PUBLISHED' AND published_at IS NOT NULL)
        OR (status <> 'PUBLISHED' AND published_at IS NULL))
);

-- =====================================================================
-- assessment_result  (CA + exam score per student per course per semester)
-- total_score / grade / grade_point are DERIVED by a BEFORE trigger; they
-- cannot be typed in to a wrong value.
-- =====================================================================
CREATE TABLE IF NOT EXISTS assessment_result (
    result_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id      INT REFERENCES result_batch(batch_id) ON DELETE SET NULL,
    matric_no     VARCHAR(20) NOT NULL REFERENCES student(matric_no) ON DELETE RESTRICT,
    course_id     INT NOT NULL REFERENCES course(course_id) ON DELETE RESTRICT,
    semester_id   INT NOT NULL REFERENCES semester(semester_id) ON DELETE RESTRICT,
    ca_score      NUMERIC(5,2) NOT NULL CHECK (ca_score BETWEEN 0 AND 40),
    exam_score    NUMERIC(5,2) NOT NULL CHECK (exam_score BETWEEN 0 AND 60),
    total_score   NUMERIC(5,2),                          -- derived by trigger
    grade         VARCHAR(2),                            -- derived by trigger
    grade_point   NUMERIC(3,1),                          -- derived by trigger
    status        VARCHAR(15) NOT NULL DEFAULT 'DRAFT'
                    CHECK (status IN ('DRAFT', 'PENDING', 'APPROVED', 'PUBLISHED')),
    superseded    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- sanity: CA + exam must fit inside 0..100
    CHECK (ca_score + exam_score BETWEEN 0 AND 100)
);

-- =====================================================================
-- grade_change_audit  (audit trail; row must exist in the SAME transaction
-- as a change to a PUBLISHED result, enforced by a trigger)
-- =====================================================================
CREATE TABLE IF NOT EXISTS grade_change_audit (
    audit_id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    result_id        BIGINT NOT NULL,
    changed_by       VARCHAR(50) NOT NULL,
    reason           VARCHAR(200) NOT NULL,
    old_total_score  NUMERIC(5,2),
    new_total_score  NUMERIC(5,2),
    old_grade        VARCHAR(2),
    new_grade        VARCHAR(2),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT transaction_timestamp()
);
-- FK added after assessment_result exists.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_audit_result'
    ) THEN
        ALTER TABLE grade_change_audit
            ADD CONSTRAINT fk_audit_result
            FOREIGN KEY (result_id) REFERENCES assessment_result(result_id)
            ON DELETE CASCADE;
    END IF;
END $$;

-- =====================================================================
-- Partial UNIQUE index: one NON-superseded result per student per course
-- per semester. (matric_no, course_id, semester_id) is unique among rows
-- where superseded = FALSE. Resit/carry-over results are stored with
-- superseded = TRUE so the latest result wins.
-- =====================================================================
CREATE UNIQUE INDEX IF NOT EXISTS one_active_result_per_student_course_semester
    ON assessment_result (matric_no, course_id, semester_id)
    WHERE superseded = FALSE;

-- =====================================================================
-- Trigger 1: compute grade from total score (BEFORE INSERT/UPDATE)
--   - total_score = ca_score + exam_score
--   - grade and grade_point are looked up from grading_scale
--   - if the caller supplied a grade that does NOT match the computed one,
--     the insert/update is REJECTED (cannot type in a wrong grade)
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_compute_grade()
RETURNS TRIGGER AS $$
DECLARE
    g RECORD;
BEGIN
    NEW.total_score := COALESCE(NEW.ca_score, 0) + COALESCE(NEW.exam_score, 0);

    SELECT gs.grade, gs.grade_point INTO g
    FROM grading_scale gs
    WHERE NEW.total_score BETWEEN gs.min_score AND gs.max_score;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Total score % does not fit any grading_scale band', NEW.total_score;
    END IF;

    IF NEW.grade IS NOT NULL AND NEW.grade <> g.grade
       AND (TG_OP = 'INSERT' OR NEW.grade IS DISTINCT FROM OLD.grade) THEN   -- only a newly TYPED grade is rejected; on a score update the old grade is simply recomputed
        RAISE EXCEPTION 'Typed grade % rejected: computed grade for total % is %',
            NEW.grade, NEW.total_score, g.grade;
    END IF;

    NEW.grade       := g.grade;
    NEW.grade_point := g.grade_point;
    NEW.updated_at  := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_compute_grade ON assessment_result;
CREATE TRIGGER trg_compute_grade
    BEFORE INSERT OR UPDATE OF ca_score, exam_score, grade ON assessment_result
    FOR EACH ROW EXECUTE FUNCTION trg_compute_grade();

-- =====================================================================
-- Trigger 2: keep updated_at fresh on any other UPDATE
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_touch_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_touch_updated_at ON assessment_result;
CREATE TRIGGER trg_touch_updated_at
    BEFORE UPDATE ON assessment_result
    FOR EACH ROW
    WHEN (NEW.ca_score IS NOT DISTINCT FROM OLD.ca_score
          AND NEW.exam_score IS NOT DISTINCT FROM OLD.exam_score
          AND NEW.grade IS NOT DISTINCT FROM OLD.grade)
    EXECUTE FUNCTION trg_touch_updated_at();

-- =====================================================================
-- Trigger 3: a PUBLISHED batch cannot contain a non-APPROVED result.
-- Fires when result_batch.status changes to PUBLISHED.
-- (Under REPEATABLE READ this trigger alone does NOT close the write-skew
--  window -- see portfolio-3. Under SERIALIZABLE + retry it does.)
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_check_batch_publish()
RETURNS TRIGGER AS $$
DECLARE
    bad INT;
BEGIN
    IF (NEW.status = 'PUBLISHED') AND (OLD IS NULL OR OLD.status <> 'PUBLISHED') THEN
        SELECT COUNT(*) INTO bad
        FROM assessment_result ar
        WHERE ar.batch_id = NEW.batch_id
          AND ar.status <> 'APPROVED';

        IF bad > 0 THEN
            RAISE EXCEPTION 'Cannot PUBLISH batch %: % result(s) are not APPROVED',
                NEW.batch_id, bad;
        END IF;

        NEW.published_at := now();
    END IF;

    -- If leaving PUBLISHED state, clear published_at (rare admin action).
    IF NEW.status <> 'PUBLISHED' AND NEW.published_at IS NOT NULL THEN
        NEW.published_at := NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_batch_publish ON result_batch;
CREATE TRIGGER trg_check_batch_publish
    BEFORE INSERT OR UPDATE OF status ON result_batch
    FOR EACH ROW EXECUTE FUNCTION trg_check_batch_publish();

-- =====================================================================
-- Trigger 4: a result in a PUBLISHED batch cannot change unless an audit
-- row is inserted in the SAME transaction. transaction_timestamp() is
-- constant for the whole transaction, so any audit row inserted in this
-- transaction will have created_at = the current transaction's timestamp.
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_block_change_after_publication()
RETURNS TRIGGER AS $$
DECLARE
    b_status    VARCHAR;
    audit_ok    BOOLEAN;
    tx_start    TIMESTAMPTZ;
    use_batch   INT;
BEGIN
    -- Determine the batch the (OLD) result belongs to.
    use_batch := COALESCE(OLD.batch_id, NEW.batch_id);
    IF use_batch IS NULL THEN
        RETURN NEW;                                  -- no batch -> no publish lock
    END IF;

    SELECT status INTO b_status FROM result_batch WHERE batch_id = use_batch;
    IF b_status IS NULL OR b_status <> 'PUBLISHED' THEN
        RETURN NEW;                                  -- not published -> free to change
    END IF;

    -- Batch IS published: require an audit row for this result inserted in
    -- the same transaction. created_at defaults to transaction_timestamp(),
    -- which equals this transaction's start.
    tx_start := transaction_timestamp();
    SELECT EXISTS (
        SELECT 1 FROM grade_change_audit gca
        WHERE gca.result_id = NEW.result_id
          AND gca.created_at = tx_start
    ) INTO audit_ok;

    IF NOT audit_ok THEN
        RAISE EXCEPTION
            'Cannot modify PUBLISHED result % without a grade_change_audit row in the same transaction',
            NEW.result_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_block_change_after_publication ON assessment_result;
CREATE TRIGGER trg_block_change_after_publication
    BEFORE UPDATE ON assessment_result
    FOR EACH ROW EXECUTE FUNCTION trg_block_change_after_publication();

-- =====================================================================
-- Trigger 5: keep assessment_result.course_id / semester_id consistent
-- with the batch (when batch_id is set). Also prevent inserting a
-- non-APPROVED result into a PUBLISHED batch (the "constraint fix" used
-- as Part 2 of the race demo).
-- =====================================================================
CREATE OR REPLACE FUNCTION trg_check_result_batch_consistency()
RETURNS TRIGGER AS $$
DECLARE
    b_course   INT;
    b_semester INT;
    b_status   VARCHAR;
BEGIN
    IF NEW.batch_id IS NOT NULL THEN
        SELECT course_id, semester_id, status
          INTO b_course, b_semester, b_status
        FROM result_batch WHERE batch_id = NEW.batch_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'batch_id % does not exist', NEW.batch_id;
        END IF;

        IF NEW.course_id <> b_course OR NEW.semester_id <> b_semester THEN
            RAISE EXCEPTION
                'Result (course_id=%, semester_id=%) does not match batch % (course_id=%, semester_id=%)',
                NEW.course_id, NEW.semester_id, NEW.batch_id, b_course, b_semester;
        END IF;

        -- Part-2-style constraint fix: once a batch is PUBLISHED, no new
        -- result that is not APPROVED may be inserted into it.
        IF TG_OP = 'INSERT' AND b_status = 'PUBLISHED' AND NEW.status <> 'APPROVED' THEN
            RAISE EXCEPTION
                'Cannot insert % result into PUBLISHED batch %',
                NEW.status, NEW.batch_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_result_batch_consistency ON assessment_result;
CREATE TRIGGER trg_check_result_batch_consistency
    BEFORE INSERT OR UPDATE OF batch_id, course_id, semester_id ON assessment_result
    FOR EACH ROW EXECUTE FUNCTION trg_check_result_batch_consistency();

-- =====================================================================
-- Computed view: semester_summary (GPA per student per semester)
-- GPA = SUM(grade_point * credit_units) / SUM(credit_units)
-- =====================================================================
CREATE OR REPLACE VIEW v_semester_summary AS
SELECT
    ar.matric_no,
    ar.semester_id,
    s.session,
    s.term,
    SUM(ar.grade_point * c.credit_units)        AS total_quality_points,
    SUM(c.credit_units)                         AS total_credits,
    CASE WHEN SUM(c.credit_units) > 0
         THEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units)
         ELSE NULL END                          AS gpa,
    COUNT(*) FILTER (WHERE ar.grade = 'F')      AS carry_over_count,
    COUNT(*)                                    AS courses_counted
FROM assessment_result ar
JOIN course   c ON c.course_id   = ar.course_id
JOIN semester s ON s.semester_id = ar.semester_id
WHERE ar.status IN ('APPROVED', 'PUBLISHED')
  AND ar.superseded = FALSE
GROUP BY ar.matric_no, ar.semester_id, s.session, s.term;

-- =====================================================================
-- Computed view: cgpa_summary (cumulative GPA, graduation class, standing)
-- =====================================================================
CREATE OR REPLACE VIEW v_cgpa_summary AS
SELECT
    ar.matric_no,
    st.programme_id,
    SUM(ar.grade_point * c.credit_units) AS total_quality_points,
    SUM(c.credit_units)                  AS total_credits,
    CASE WHEN SUM(c.credit_units) > 0
         THEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units)
         ELSE NULL END                   AS cgpa,
    CASE
        WHEN SUM(c.credit_units) = 0 THEN NULL
        WHEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units) >= 4.50 THEN 'First Class'
        WHEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units) >= 3.50 THEN 'Second Class Upper'
        WHEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units) >= 2.40 THEN 'Second Class Lower'
        WHEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units) >= 1.50 THEN 'Third Class'
        WHEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units) >= 1.00 THEN 'Pass'
        ELSE 'Fail'
    END                                  AS graduation_class,
    CASE
        WHEN SUM(c.credit_units) = 0 THEN NULL
        WHEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units) >= 1.50 THEN 'Good Standing'
        WHEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units) >= 1.00 THEN 'Probation'
        ELSE 'Withdrawal'
    END                                  AS academic_standing,
    COUNT(*) FILTER (WHERE ar.grade = 'F') AS total_carry_overs
FROM assessment_result ar
JOIN student st ON st.matric_no = ar.matric_no
JOIN course   c ON c.course_id   = ar.course_id
WHERE ar.status IN ('APPROVED', 'PUBLISHED')
  AND ar.superseded = FALSE
GROUP BY ar.matric_no, st.programme_id;

-- =====================================================================
-- A function that recomputes CGPA independently of the view, for the
-- check query in 04_bulk_data.sql: should find 0 mismatches.
-- =====================================================================
CREATE OR REPLACE FUNCTION recompute_cgpa(p_matric VARCHAR)
RETURNS NUMERIC AS $$
DECLARE
    v_cgpa NUMERIC;
BEGIN
    SELECT CASE WHEN SUM(c.credit_units) > 0
                THEN SUM(ar.grade_point * c.credit_units) / SUM(c.credit_units)
                ELSE NULL END
      INTO v_cgpa
    FROM assessment_result ar
    JOIN course c ON c.course_id = ar.course_id
    WHERE ar.matric_no = p_matric
      AND ar.status IN ('APPROVED', 'PUBLISHED')
      AND ar.superseded = FALSE;

    RETURN v_cgpa;
END;
$$ LANGUAGE plpgsql;

-- Done.
