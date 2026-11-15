# Portfolio 1 — Database Design

**Database:** `resultsys` (PostgreSQL 16, Unix socket, no passwords, no TCP)
**System:** Ibom Crown University Result Processing System

## What this portfolio builds

The relational core of the result-processing subsystem for Ibom Crown University, Uyo — Akwa Ibom State. Eleven tables in Third Normal Form, plus five triggers that enforce business rules, one partial UNIQUE index, and two computed GPA/CGPA views.

## Files

| File | What it does |
| --- | --- |
| `01_schema.sql` | Creates the 11 tables, all PK/FK/UNIQUE/CHECK constraints, the partial UNIQUE index `one_active_result_per_student_course_semester`, five triggers, and the two GPA views. Sets the database time zone to `Africa/Lagos`. |
| `02_indexes.sql` | B-tree index on every FK column, plus analytical indexes used by triggers and reports (a partial index on `(matric_no) WHERE superseded = FALSE AND status IN ('APPROVED','PUBLISHED')` drives the GPA views). |
| `03_seed_data.sql` | Reference data: 4 faculties, 8 departments, 5 programmes, 12 lecturers, 24 courses, the 6-row Nigerian grading scale, 5 semesters (relative to today), 6 sample students, 4 sample batches and a handful of results. |
| `04_bulk_data.sql` | Adds 2,000 students and ~60,000 `assessment_result` rows using `generate_series` (no Python loops). Past semesters are `PUBLISHED`; the current semester (`2024/2025` second) still has `DRAFT`/`PENDING` rows for the concurrency demos. Closes with a CGPA self-check that recomputes CGPA from raw rows and reports 0 mismatches against `v_cgpa_summary`. |
| `05_constraint_tests.sql` | 10 tests that MUST fail on the intended constraint, plus 1 control that MUST succeed. Each test builds its own data inside `BEGIN ... ROLLBACK` and prints PASS / FAIL. |

## Schema at a glance

```
faculty 1--* department 1--* programme 1--* student
                   \
                    *-- lecturer
                    *-- course 1--* result_batch 1--* assessment_result
                                                          |
                                                   grading_scale (derives grade)
                                                          |
                                                   grade_change_audit (audit trail)

semester 1--* result_batch
        \--* assessment_result

Views: v_semester_summary (GPA per student per semester)
       v_cgpa_summary     (CGPA, graduation class, academic standing per student)
```

## Triggers

| # | Trigger | Business rule |
| --- | --- | --- |
| 1 | `trg_compute_grade` (BEFORE INSERT/UPDATE on `assessment_result`) | `total_score = ca_score + exam_score`; `grade` and `grade_point` are looked up from `grading_scale` and **cannot be typed in** — typing a wrong grade is rejected. |
| 2 | `trg_touch_updated_at` (BEFORE UPDATE) | Keeps `updated_at` fresh for updates that do not change scores. |
| 3 | `trg_check_batch_publish` (BEFORE INSERT/UPDATE on `result_batch`) | A `PUBLISHED` batch cannot contain a result that is not `APPROVED`. Sets `published_at` automatically. |
| 4 | `trg_block_change_after_publication` (BEFORE UPDATE on `assessment_result`) | A result in a `PUBLISHED` batch cannot change unless a `grade_change_audit` row is inserted **in the same transaction** (detected via `transaction_timestamp()`). |
| 5 | `trg_check_result_batch_consistency` (BEFORE INSERT/UPDATE on `assessment_result`) | `assessment_result.course_id`/`semester_id` must match the batch; a non-`APPROVED` result cannot be inserted into a `PUBLISHED` batch. |

## Partial UNIQUE index

```sql
CREATE UNIQUE INDEX one_active_result_per_student_course_semester
    ON assessment_result (matric_no, course_id, semester_id)
    WHERE superseded = FALSE;
```

This enforces "one non-superseded result per student per course per semester". A failed result that is later re-taken is marked `superseded = TRUE`, so the new resit row wins.

## How to run

```bash
psql -d resultsys -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -d resultsys -v ON_ERROR_STOP=1 -f 02_indexes.sql
psql -d resultsys -v ON_ERROR_STOP=1 -f 03_seed_data.sql
psql -d resultsys -v ON_ERROR_STOP=1 -f 04_bulk_data.sql
psql -d resultsys -v ON_ERROR_STOP=1 -f 05_constraint_tests.sql
```

## Expected counts after bulk load

After `04_bulk_data.sql` runs:

| Table | Approx rows |
| --- | --- |
| `student` | ~2,006 |
| `course` | 24 |
| `result_batch` | ~96 |
| `assessment_result` | ~60,000 |

The exact count of `assessment_result` depends on how many `(student, batch)` pairs exist; the insert is clamped to `n_students × n_batches` so every row succeeds.

## Constraint test output

After running `05_constraint_tests.sql` you should see ten `PASS: test N -- …` lines and one `PASS (control): test 11 …` line. Paste the real output below:

```
[paste real output here]
```
