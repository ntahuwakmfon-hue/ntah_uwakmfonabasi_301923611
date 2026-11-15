-- 03_seed_data.sql
-- Purpose: Seed Ibom Crown University with realistic reference data and a
-- small set of sample students, courses, batches and results. Larger bulk
-- data (2,000 students, 60,000 results) is loaded separately by
-- 04_bulk_data.sql. Idempotent: uses INSERT ... ON CONFLICT DO NOTHING.
-- Runs top to bottom with: psql -d resultsys -v ON_ERROR_STOP=1 -f 03_seed_data.sql

SET timezone TO 'Africa/Lagos';

-- =====================================================================
-- Faculties
-- =====================================================================
INSERT INTO faculty (faculty_code, name, dean_name, location) VALUES
    ('FOS', 'Faculty of Science',            'Prof. Ekaette Iniodu Bassey',  'Uyo, Akwa Ibom'),
    ('FOE', 'Faculty of Engineering',        'Dr. Ntiedo Akpan Udoh',        'Uyo, Akwa Ibom'),
    ('FSS', 'Faculty of Social Sciences',    'Prof. Mfon Udo Okon',          'Eket, Akwa Ibom'),
    ('FOH', 'Faculty of Humanities',         'Dr. Inyang Effiong Eshiet',    'Calabar, Cross River')
ON CONFLICT (faculty_code) DO NOTHING;

-- =====================================================================
-- Departments (8)
-- =====================================================================
INSERT INTO department (dept_code, faculty_id, name, hod_name) VALUES
    ('CSC', 1, 'Department of Computer Science',       'Dr. Uwakmfon Edet Nkanta'),
    ('MTH', 1, 'Department of Mathematics',            'Prof. Abasi Ubong Umoh'),
    ('PHY', 1, 'Department of Physics',                'Dr. Comfort Iniobong Asuquo'),
    ('CEN', 2, 'Department of Computer Engineering',   'Dr. Victor Samuel Ekanem'),
    ('ECN', 3, 'Department of Economics',              'Prof. Mary James Udoudo'),
    ('ACC', 3, 'Department of Accountancy',            'Dr. Sarah Peter Bassey'),
    ('EDU', 4, 'Department of Educational Management', 'Dr. Esther David Mark'),
    ('LAW', 4, 'Department of Jurisprudence',          'Prof. Paul Joseph Effiong')
ON CONFLICT (dept_code) DO NOTHING;

-- =====================================================================
-- Programmes (5)
-- =====================================================================
INSERT INTO programme (dept_id, code, name, duration_years, award) VALUES
    (1, 'BSC-CSC', 'B.Sc. Computer Science',        4, 'B.Sc.'),
    (4, 'BENG-CEN','B.Eng. Computer Engineering',   5, 'B.Eng.'),
    (5, 'BSC-ECN', 'B.Sc. Economics',               4, 'B.Sc.'),
    (6, 'BSC-ACC', 'B.Sc. Accountancy',             4, 'B.Sc.'),
    (7, 'BED-EDM', 'B.Ed. Educational Management',  4, 'B.Ed.')
ON CONFLICT (code) DO NOTHING;

-- =====================================================================
-- Lecturers (12)  -- gender-matched Nigerian names + titles
-- =====================================================================
INSERT INTO lecturer (dept_id, staff_no, title, first_name, last_name, email) VALUES
    (1, 'ICU/STAFF/001', 'Dr.',   'Uwakmfon', 'Nkanta',   'uwakmfon.nkanta@ibomcrown.edu.ng'),
    (1, 'ICU/STAFF/002', 'Prof.', 'Ekaette',  'Bassey',   'ekaette.bassey@ibomcrown.edu.ng'),
    (1, 'ICU/STAFF/003', 'Mr.',   'Ekemini',  'Udoh',     'ekemini.udoh@ibomcrown.edu.ng'),
    (2, 'ICU/STAFF/004', 'Prof.', 'Abasi',    'Umoh',     'abasi.umoh@ibomcrown.edu.ng'),
    (2, 'ICU/STAFF/005', 'Mrs.',  'Comfort',  'Asuquo',   'comfort.asuquo@ibomcrown.edu.ng'),
    (3, 'ICU/STAFF/006', 'Dr.',   'Ntiedo',   'Akpan',    'ntiedo.akpan@ibomcrown.edu.ng'),
    (4, 'ICU/STAFF/007', 'Dr.',   'Victor',   'Ekanem',   'victor.ekanem@ibomcrown.edu.ng'),
    (4, 'ICU/STAFF/008', 'Mr.',   'Daniel',   'Joseph',   'daniel.joseph@ibomcrown.edu.ng'),
    (5, 'ICU/STAFF/009', 'Prof.', 'Mary',     'Udoudo',   'mary.udoudo@ibomcrown.edu.ng'),
    (5, 'ICU/STAFF/010', 'Dr.',   'Sarah',    'Bassey',   'sarah.bassey@ibomcrown.edu.ng'),
    (6, 'ICU/STAFF/011', 'Ms.',   'Rita',     'Okon',     'rita.okon@ibomcrown.edu.ng'),
    (7, 'ICU/STAFF/012', 'Dr.',   'Esther',   'Mark',     'esther.mark@ibomcrown.edu.ng')
ON CONFLICT (staff_no) DO NOTHING;

-- =====================================================================
-- Courses (24)  -- 100/200/300/400 level, 2-4 credit units each
-- =====================================================================
INSERT INTO course (dept_id, code, title, credit_units, level, semester_offered) VALUES
    (1, 'CSC101', 'Introduction to Computer Science',  3, 100, 'FIRST'),
    (1, 'CSC102', 'Introduction to Problem Solving',   3, 100, 'SECOND'),
    (1, 'CSC201', 'Data Structures and Algorithms',    3, 200, 'FIRST'),
    (1, 'CSC202', 'Database Systems',                  4, 200, 'SECOND'),
    (1, 'CSC203', 'Object Oriented Programming',       3, 200, 'FIRST'),
    (1, 'CSC301', 'Operating Systems',                 4, 300, 'FIRST'),
    (1, 'CSC302', 'Computer Networks',                 3, 300, 'SECOND'),
    (1, 'CSC303', 'Software Engineering',              3, 300, 'SECOND'),
    (1, 'CSC401', 'Distributed Systems',               4, 400, 'FIRST'),
    (1, 'CSC402', 'Artificial Intelligence',           3, 400, 'SECOND'),
    (2, 'MTH101', 'Elementary Mathematics I',          3, 100, 'FIRST'),
    (2, 'MTH102', 'Elementary Mathematics II',         3, 100, 'SECOND'),
    (2, 'MTH201', 'Linear Algebra',                    3, 200, 'FIRST'),
    (3, 'PHY101', 'General Physics I',                 3, 100, 'FIRST'),
    (4, 'CEN101', 'Engineering Drawing',               2, 100, 'FIRST'),
    (4, 'CEN201', 'Digital Logic Design',              3, 200, 'FIRST'),
    (4, 'CEN301', 'Microprocessor Systems',            4, 300, 'SECOND'),
    (5, 'ECN101', 'Introduction to Economics',         3, 100, 'FIRST'),
    (5, 'ECN201', 'Microeconomics',                    3, 200, 'FIRST'),
    (5, 'ECN301', 'Macroeconomics',                    3, 300, 'SECOND'),
    (6, 'ACC101', 'Principles of Accounting I',        3, 100, 'FIRST'),
    (6, 'ACC201', 'Financial Accounting',              4, 200, 'SECOND'),
    (7, 'EDU101', 'Foundations of Education',          2, 100, 'FIRST'),
    (7, 'EDU201', 'Educational Psychology',            3, 200, 'SECOND')
ON CONFLICT (code) DO NOTHING;

-- =====================================================================
-- Grading scale (Nigerian 5-point)
-- =====================================================================
INSERT INTO grading_scale (grade, min_score, max_score, grade_point, interpretation) VALUES
    ('A', 70.00, 100.00, 5.0, 'Excellent'),
    ('B', 60.00,  69.99, 4.0, 'Very Good'),
    ('C', 50.00,  59.99, 3.0, 'Good'),
    ('D', 45.00,  49.99, 2.0, 'Fair'),
    ('E', 40.00,  44.99, 1.0, 'Pass'),
    ('F',  0.00,  39.99, 0.0, 'Fail')
ON CONFLICT (grade) DO NOTHING;

-- =====================================================================
-- Semesters (5) -- RELATIVE to today.
-- Two past sessions (4 semesters) + the current semester.
-- =====================================================================
INSERT INTO semester (session, term, start_date, end_date) VALUES
    ('2023/2024', 'FIRST',  (CURRENT_DATE - INTERVAL '18 months')::date,
                  (CURRENT_DATE - INTERVAL '12 months')::date),
    ('2023/2024', 'SECOND', (CURRENT_DATE - INTERVAL '12 months')::date,
                  (CURRENT_DATE - INTERVAL '6 months')::date),
    ('2024/2025', 'FIRST',  (CURRENT_DATE - INTERVAL '6 months')::date,
                  (CURRENT_DATE - INTERVAL '1 month')::date),
    ('2024/2025', 'SECOND', (CURRENT_DATE - INTERVAL '1 month')::date,
                  (CURRENT_DATE + INTERVAL '3 months')::date),
    -- a near-future semester used only for partitioning demo coverage
    ('2025/2026', 'FIRST',  (CURRENT_DATE + INTERVAL '3 months')::date,
                  (CURRENT_DATE + INTERVAL '9 months')::date)
ON CONFLICT (session, term) DO NOTHING;

-- =====================================================================
-- Sample students (6)  -- the bulk generator adds ~2,000 more
-- matric_no pattern: ICU/<year>/<5-digit no>
-- =====================================================================
INSERT INTO student (matric_no, programme_id, first_name, last_name, gender, level, status, session_admitted, state_of_origin, tuition_ngn) VALUES
    ('ICU/2023/00001', 1, 'Uwakmfonabasi', 'Ntah',     'M', 200, 'active',    '2022/2023', 'Akwa Ibom', 450000.00),
    ('ICU/2023/00002', 1, 'Emem',          'Edet',     'F', 200, 'active',    '2022/2023', 'Akwa Ibom', 450000.00),
    ('ICU/2023/00003', 2, 'Akpan',         'Inyang',   'M', 200, 'active',    '2022/2023', 'Akwa Ibom', 520000.00),
    ('ICU/2024/00004', 1, 'Ekaette',       'Bassey',   'F', 100, 'active',    '2023/2024', 'Akwa Ibom', 450000.00),
    ('ICU/2024/00005', 3, 'Iniodu',        'Udoh',     'M', 100, 'active',    '2023/2024', 'Akwa Ibom', 430000.00),
    ('ICU/2022/00006', 4, 'Affiong',       'Eshiet',   'F', 300, 'active',    '2021/2022', 'Akwa Ibom', 480000.00)
ON CONFLICT (matric_no) DO NOTHING;

-- =====================================================================
-- Sample result batches (4)  -- one past-semester published, one current
-- =====================================================================
INSERT INTO result_batch (course_id, semester_id, dept_id, lecturer_id, status, published_at) VALUES
    -- batch 1: CSC101 in 2023/2024 first semester (already published)
    ( (SELECT course_id   FROM course  WHERE code = 'CSC101'),
      (SELECT semester_id FROM semester WHERE session = '2023/2024' AND term = 'FIRST'),
      (SELECT dept_id      FROM department WHERE dept_code = 'CSC'),
      (SELECT lecturer_id  FROM lecturer  WHERE staff_no = 'ICU/STAFF/001'),
      'PUBLISHED',
      (CURRENT_TIMESTAMP - INTERVAL '13 months') ),
    -- batch 2: CSC201 in 2024/2025 first semester (already published)
    ( (SELECT course_id   FROM course  WHERE code = 'CSC201'),
      (SELECT semester_id FROM semester WHERE session = '2024/2025' AND term = 'FIRST'),
      (SELECT dept_id      FROM department WHERE dept_code = 'CSC'),
      (SELECT lecturer_id  FROM lecturer  WHERE staff_no = 'ICU/STAFF/001'),
      'PUBLISHED',
      (CURRENT_TIMESTAMP - INTERVAL '2 months') ),
    -- batch 3: CSC202 in 2024/2025 second semester (pending moderation)
    ( (SELECT course_id   FROM course  WHERE code = 'CSC202'),
      (SELECT semester_id FROM semester WHERE session = '2024/2025' AND term = 'SECOND'),
      (SELECT dept_id      FROM department WHERE dept_code = 'CSC'),
      (SELECT lecturer_id  FROM lecturer  WHERE staff_no = 'ICU/STAFF/002'),
      'PENDING',
      NULL ),
    -- batch 4: MTH101 in 2023/2024 first semester (published)
    ( (SELECT course_id   FROM course  WHERE code = 'MTH101'),
      (SELECT semester_id FROM semester WHERE session = '2023/2024' AND term = 'FIRST'),
      (SELECT dept_id      FROM department WHERE dept_code = 'MTH'),
      (SELECT lecturer_id  FROM lecturer  WHERE staff_no = 'ICU/STAFF/004'),
      'PUBLISHED',
      (CURRENT_TIMESTAMP - INTERVAL '13 months') )
ON CONFLICT (course_id, semester_id, dept_id) DO NOTHING;

-- =====================================================================
-- Sample results (a handful) for the seeded students + batches above.
-- total_score / grade / grade_point are derived by the trigger; we leave
-- them NULL in the INSERT.
-- =====================================================================
INSERT INTO assessment_result
    (batch_id, matric_no, course_id, semester_id, ca_score, exam_score, status, superseded)
SELECT b.batch_id, s.matric_no, c.course_id, sem.semester_id,
       v.ca, v.exam,
       'APPROVED',   -- a published batch holds only APPROVED results
       FALSE
FROM (VALUES
    -- batch 1 (CSC101, 2023/2024 first, PUBLISHED)
    ('ICU/2023/00001', 'CSC101', '2023/2024', 'FIRST', 32.50, 58.00),
    ('ICU/2023/00002', 'CSC101', '2023/2024', 'FIRST', 28.00, 41.00),
    ('ICU/2024/00004', 'CSC101', '2023/2024', 'FIRST', 22.00, 18.00),
    -- batch 2 (CSC201, 2024/2025 first, PUBLISHED)
    ('ICU/2023/00001', 'CSC201', '2024/2025', 'FIRST', 35.00, 51.00),
    ('ICU/2023/00002', 'CSC201', '2024/2025', 'FIRST', 30.00, 39.00),
    -- batch 4 (MTH101, 2023/2024 first, PUBLISHED)
    ('ICU/2024/00005', 'MTH101', '2023/2024', 'FIRST', 25.00, 25.00)
) AS v(matric, code, session, term, ca, exam)
JOIN student   s   ON s.matric_no   = v.matric
JOIN course    c   ON c.code        = v.code
JOIN semester  sem ON sem.session   = v.session AND sem.term = v.term
JOIN result_batch b ON b.course_id = c.course_id AND b.semester_id = sem.semester_id
ON CONFLICT DO NOTHING;

-- =====================================================================
-- Sanity: print counts after seed.
-- =====================================================================
SELECT 'faculty'   AS table_name, count(*) FROM faculty
UNION ALL SELECT 'department',   count(*) FROM department
UNION ALL SELECT 'programme',    count(*) FROM programme
UNION ALL SELECT 'lecturer',     count(*) FROM lecturer
UNION ALL SELECT 'course',       count(*) FROM course
UNION ALL SELECT 'grading_scale',count(*) FROM grading_scale
UNION ALL SELECT 'semester',     count(*) FROM semester
UNION ALL SELECT 'student',      count(*) FROM student
UNION ALL SELECT 'result_batch', count(*) FROM result_batch
UNION ALL SELECT 'assessment_result', count(*) FROM assessment_result;
