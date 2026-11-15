-- 01_partitioning.sql
-- Purpose: Demonstrate monthly RANGE partitioning of the biggest table
-- (assessment_result) on its created_at column.
--   - Creates a partitioned copy `assessment_result_part` whose PRIMARY KEY
--     is (result_id, created_at) -- unique keys MUST include the partition key.
--   - Uses a DO loop to create one partition per month covering EVERY month
--     present in the source data PLUS next month, plus a DEFAULT partition.
--   - Migrates all rows from assessment_result into the partitioned table.
--   - Adds a few extra back-dated rows so more than one partition has data.
--   - Prints the row count per partition and a pruned one-month EXPLAIN ANALYZE.
-- Note: PG16 does not allow exclusion constraints on a partitioned parent;
-- none are used here.
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 01_partitioning.sql

SET timezone TO 'Africa/Lagos';
\pset pager off

-- =====================================================================
-- 1. Drop the partitioned table if it already exists (cascades partitions).
-- =====================================================================
DROP TABLE IF EXISTS assessment_result_part CASCADE;

-- =====================================================================
-- 2. Create the partitioned parent.
--    PK is (result_id, created_at) because every unique key on a
--    partitioned table must include the partition key (created_at).
--    The CHECK constraints from assessment_result are kept so inserts
--    are still validated. Triggers are NOT replicated on this copy --
--    we are demonstrating partitioning, not re-running the business rules.
-- =====================================================================
CREATE TABLE assessment_result_part (
    result_id     BIGINT       NOT NULL,
    batch_id      INT,
    matric_no     VARCHAR(20)  NOT NULL,
    course_id     INT          NOT NULL,
    semester_id   INT          NOT NULL,
    ca_score      NUMERIC(5,2) NOT NULL CHECK (ca_score BETWEEN 0 AND 40),
    exam_score    NUMERIC(5,2) NOT NULL CHECK (exam_score BETWEEN 0 AND 60),
    total_score   NUMERIC(5,2),
    grade         VARCHAR(2),
    grade_point   NUMERIC(3,1),
    status        VARCHAR(15)  NOT NULL DEFAULT 'DRAFT'
                    CHECK (status IN ('DRAFT', 'PENDING', 'APPROVED', 'PUBLISHED')),
    superseded    BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CHECK (ca_score + exam_score BETWEEN 0 AND 100),
    PRIMARY KEY (result_id, created_at)
) PARTITION BY RANGE (created_at);

-- =====================================================================
-- 3. DO loop: create one monthly partition for EVERY month present in
--    assessment_result.created_at, PLUS next month, PLUS a DEFAULT.
-- =====================================================================
DO $$
DECLARE
    min_month DATE;
    max_month DATE;
    m         DATE;
    next_m    DATE;
    part_name TEXT;
BEGIN
    SELECT date_trunc('month', MIN(created_at))::date INTO min_month
      FROM assessment_result;
    SELECT date_trunc('month', MAX(created_at))::date INTO max_month
      FROM assessment_result;

    -- Cover next month as well, so inserts dated "next month" still land
    -- in a real partition rather than the DEFAULT.
    max_month := (max_month + INTERVAL '1 month')::date;

    RAISE NOTICE 'Creating monthly partitions from % to % (inclusive)',
        to_char(min_month, 'YYYY-MM-DD'), to_char(max_month, 'YYYY-MM-DD');

    m := min_month;
    WHILE m <= max_month LOOP
        next_m    := (m + INTERVAL '1 month')::date;
        part_name := 'ar_part_' || to_char(m, 'YYYY_MM');
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF assessment_result_part '
            'FOR VALUES FROM (%L) TO (%L)',
            part_name, m, next_m
        );
        RAISE NOTICE '  created partition % for [%,%]', part_name, m, next_m;
        m := next_m;
    END LOOP;

    -- DEFAULT partition catches anything outside the monthly range.
    EXECUTE 'CREATE TABLE IF NOT EXISTS ar_part_default '
            'PARTITION OF assessment_result_part DEFAULT';
    RAISE NOTICE '  created DEFAULT partition ar_part_default';
END $$;

-- =====================================================================
-- 4. Migrate all rows from assessment_result into the partitioned table.
--    created_at is preserved (so each row lands in its correct partition).
-- =====================================================================
INSERT INTO assessment_result_part
    (result_id, batch_id, matric_no, course_id, semester_id,
     ca_score, exam_score, total_score, grade, grade_point,
     status, superseded, created_at, updated_at)
SELECT
    result_id, batch_id, matric_no, course_id, semester_id,
    ca_score, exam_score, total_score, grade, grade_point,
    status, superseded, created_at, updated_at
FROM assessment_result
ON CONFLICT DO NOTHING;

-- =====================================================================
-- 5. Add a few back-dated rows so more than one monthly partition has
--    data -- otherwise every row lands in the current month only.
--    We use NULL batch_id so the consistency trigger on the *original*
--    table does not apply (we are inserting into the partitioned copy,
--    which has no triggers).
-- =====================================================================
INSERT INTO assessment_result_part
    (result_id, matric_no, course_id, semester_id,
     ca_score, exam_score, total_score, grade, grade_point,
     status, superseded, created_at, updated_at)
SELECT
    -- synthetic negative result_id so we never collide with the identity sequence
    -(g + 100000),
    'ICU/2024/' || lpad((mod(g, 2000) + 100)::text, 5, '0'),
    (mod(g, 24) + 1),
    (mod(g, 5) + 1),
    (random() * 30 + 8)::numeric(5,2),
    (random() * 50 + 5)::numeric(5,2),
    0.00,  -- filled in below
    'F',
    0.0,
    'APPROVED',
    FALSE,
    -- created_at spread across the last 5 months + 1 future month
    date_trunc('month', CURRENT_DATE)::timestamptz
        - make_interval(months => mod(g, 6))
        + make_interval(secs => g),
    date_trunc('month', CURRENT_DATE)::timestamptz
        - make_interval(months => mod(g, 6))
        + make_interval(secs => g)
FROM generate_series(1, 300) g
ON CONFLICT DO NOTHING;

-- =====================================================================
-- 6. Print rows per partition.
--    We use a dynamic query per child table because partition row counts
--    are not stored in a single catalog view directly.
-- =====================================================================
\echo '==== Rows per partition ===='
DO $$
DECLARE
    r RECORD;
    cnt BIGINT;
BEGIN
    FOR r IN
        SELECT c.relname AS partition_name
        FROM pg_inherits i
        JOIN pg_class c ON c.oid = i.inhrelid
        WHERE i.inhparent = 'assessment_result_part'::regclass
        ORDER BY c.relname
    LOOP
        EXECUTE format('SELECT count(*) FROM %I', r.partition_name) INTO cnt;
        RAISE NOTICE 'partition %: % rows', r.partition_name, cnt;
    END LOOP;
END $$;

-- Also a tabular summary that is easy to copy into the README.
SELECT
    c.relname AS partition_name,
    pg_stat_get_tuples_returned(c.oid) AS approx_rows_returned_by_stats
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE i.inhparent = 'assessment_result_part'::regclass
ORDER BY c.relname;

-- =====================================================================
-- 7. Pruned one-month EXPLAIN ANALYZE.
--    The WHERE clause restricts created_at to a single month, so the
--    planner should prune to that one partition only.
-- =====================================================================
\echo '==== Pruned EXPLAIN ANALYZE: one month only ===='
EXPLAIN (ANALYZE, BUFFERS)
SELECT matric_no, course_id, total_score, grade
FROM assessment_result_part
WHERE created_at >= date_trunc('month', CURRENT_DATE)::timestamptz
  AND created_at <  (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::timestamptz;

-- =====================================================================
-- 8. A second EXPLAIN ANALYZE that touches multiple months -- should
--    scan multiple partitions and NOT prune.
-- =====================================================================
\echo '==== EXPLAIN ANALYZE: all data (no pruning) ===='
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM assessment_result_part;

\echo '==== End of partitioning demo ===='
