// 02_data_and_queries.js
// Purpose: Seed the two validated collections with a small set of
// representative Ibom Crown documents, then run three aggregation
// pipelines. Uses NumberInt/NumberLong/Double for typed numbers.
// Run with: mongosh resultsys 02_data_and_queries.js

db = db.getSiblingDB("resultsys");

// ---------------------------------------------------------------------
// 1. Seed result_audit_log with one event of each type.
//    result_id is NumberLong; approved_count is NumberInt; scores are Double.
// ---------------------------------------------------------------------
db.result_audit_log.deleteMany({});

db.result_audit_log.insertMany([
  {
    _id: ObjectId(),
    event_type: "GRADE_CHANGE",
    result_id: NumberLong(100001),
    matric_no: "ICU/2023/00001",
    course_code: "CSC101",
    occurred_at: new ISODate("2025-11-01T10:00:00Z"),
    actor: "Dr. Uwakmfon Nkanta",
    detail: {
      _id: ObjectId(),
      old_grade: "F",
      new_grade: "C",
      old_total_score: Double(28.0),
      new_total_score: Double(55.0),
      reason: "Resit script re-marked by external examiner",
      changed_in_tx: new ISODate("2025-11-01T10:00:00Z")
    }
  },
  {
    _id: ObjectId(),
    event_type: "RESULT_APPROVED",
    result_id: NumberLong(100002),
    matric_no: "ICU/2023/00002",
    course_code: "CSC201",
    occurred_at: new ISODate("2025-11-02T09:30:00Z"),
    actor: "Exam Officer, CSC",
    detail: {
      _id: ObjectId(),
      approver: "Dr. Uwakmfon Nkanta",
      previous_status: "PENDING",
      new_status: "APPROVED",
      moderation_notes: "CA total reconciled; grade C confirmed."
    }
  },
  {
    _id: ObjectId(),
    event_type: "BATCH_PUBLISHED",
    result_id: NumberLong(0),                 // batch-level event, no single result
    matric_no: "",                            // batch-level event, no single student
    course_code: "MTH101",
    occurred_at: new ISODate("2025-11-03T14:00:00Z"),
    actor: "Senate Secretary",
    detail: {
      _id: ObjectId(),
      batch_id: NumberLong(2),
      course_code: "MTH101",
      semester_session: "2024/2025",
      semester_term: "FIRST",
      approved_count: NumberInt(48),
      approved_by_senate: true
    }
  },
  {
    _id: ObjectId(),
    event_type: "GRADE_CHANGE",
    result_id: NumberLong(100003),
    matric_no: "ICU/2024/00005",
    course_code: "ECN101",
    occurred_at: new ISODate("2025-11-05T11:15:00Z"),
    actor: "Dr. Mary Udoudo",
    detail: {
      _id: ObjectId(),
      old_grade: "E",
      new_grade: "B",
      old_total_score: Double(42.0),
      new_total_score: Double(63.0),
      reason: "CA score entered wrong (10 instead of 31)",
      changed_in_tx: new ISODate("2025-11-05T11:15:00Z")
    }
  },
  {
    _id: ObjectId(),
    event_type: "BATCH_PUBLISHED",
    result_id: NumberLong(0),
    matric_no: "",
    course_code: "CSC101",
    occurred_at: new ISODate("2025-11-06T16:00:00Z"),
    actor: "Senate Secretary",
    detail: {
      _id: ObjectId(),
      batch_id: NumberLong(1),
      course_code: "CSC101",
      semester_session: "2023/2024",
      semester_term: "FIRST",
      approved_count: NumberInt(35),
      approved_by_senate: true
    }
  }
]);

print("---- result_audit_log seed count: " + db.result_audit_log.countDocuments() + " ----");

// ---------------------------------------------------------------------
// 2. Seed transcript_documents with five snapshots.
//    Numbers: credit_units = NumberInt, scores and grade_point = Double,
//    cgpa and total_credits typed accordingly.
// ---------------------------------------------------------------------
db.transcript_documents.deleteMany({});

function courseLine(code, title, units, ca, ex, grade, gp, session, term) {
  return {
    _id: ObjectId(),
    course_code: code,
    course_title: title,
    credit_units: NumberInt(units),
    ca_score: Double(ca),
    exam_score: Double(ex),
    total_score: Double(ca + ex),
    grade: grade,
    grade_point: Double(gp),
    semester_session: session,
    semester_term: term
  };
}

db.transcript_documents.insertMany([
  {
    _id: ObjectId(),
    transcript_id: "TR/2025/0001",
    matric_no: "ICU/2023/00001",
    student_name: "Uwakmfonabasi Ntah",
    programme: "B.Sc. Computer Science",
    programme_code: "BSC-CSC",
    generated_at: new ISODate("2025-11-10T08:00:00Z"),
    cgpa: Double(4.62),
    graduation_class: "First Class",
    academic_standing: "Good Standing",
    total_credits: NumberInt(120),
    issued: true,
    course_lines: [
      courseLine("CSC101", "Introduction to Computer Science", 3, 32, 58, "A", 5.0, "2023/2024", "FIRST"),
      courseLine("CSC201", "Data Structures and Algorithms",  3, 35, 51, "A", 5.0, "2024/2025", "FIRST"),
      courseLine("MTH101", "Elementary Mathematics I",        3, 30, 40, "B", 4.0, "2023/2024", "FIRST")
    ]
  },
  {
    _id: ObjectId(),
    transcript_id: "TR/2025/0002",
    matric_no: "ICU/2023/00002",
    student_name: "Emem Edet",
    programme: "B.Sc. Computer Science",
    programme_code: "BSC-CSC",
    generated_at: new ISODate("2025-11-10T08:00:00Z"),
    cgpa: Double(3.85),
    graduation_class: "Second Class Upper",
    academic_standing: "Good Standing",
    total_credits: NumberInt(120),
    issued: true,
    course_lines: [
      courseLine("CSC101", "Introduction to Computer Science", 3, 28, 41, "B", 4.0, "2023/2024", "FIRST"),
      courseLine("CSC201", "Data Structures and Algorithms",  3, 30, 39, "C", 3.0, "2024/2025", "FIRST")
    ]
  },
  {
    _id: ObjectId(),
    transcript_id: "TR/2025/0003",
    matric_no: "ICU/2024/00005",
    student_name: "Iniodu Udoh",
    programme: "B.Sc. Economics",
    programme_code: "BSC-ECN",
    generated_at: new ISODate("2025-11-10T08:00:00Z"),
    cgpa: Double(2.85),
    graduation_class: "Second Class Lower",
    academic_standing: "Good Standing",
    total_credits: NumberInt(60),
    issued: false,
    course_lines: [
      courseLine("ECN101", "Introduction to Economics", 3, 25, 25, "C", 3.0, "2023/2024", "FIRST"),
      courseLine("MTH101", "Elementary Mathematics I",  3, 20, 18, "F", 0.0, "2023/2024", "FIRST")
    ]
  },
  {
    _id: ObjectId(),
    transcript_id: "TR/2025/0004",
    matric_no: "ICU/2022/00006",
    student_name: "Affiong Eshiet",
    programme: "B.Sc. Accountancy",
    programme_code: "BSC-ACC",
    generated_at: new ISODate("2025-11-10T08:00:00Z"),
    cgpa: Double(1.30),
    graduation_class: "Pass",
    academic_standing: "Probation",
    total_credits: NumberInt(90),
    issued: false,
    course_lines: [
      courseLine("ACC101", "Principles of Accounting I", 3, 18, 22, "E", 1.0, "2022/2023", "FIRST"),
      courseLine("ACC201", "Financial Accounting",       4, 15, 20, "E", 1.0, "2023/2024", "SECOND")
    ]
  },
  {
    _id: ObjectId(),
    transcript_id: "TR/2025/0005",
    matric_no: "ICU/2023/00003",
    student_name: "Akpan Inyang",
    programme: "B.Eng. Computer Engineering",
    programme_code: "BENG-CEN",
    generated_at: new ISODate("2025-11-10T08:00:00Z"),
    cgpa: Double(0.85),
    graduation_class: "Fail",
    academic_standing: "Withdrawal",
    total_credits: NumberInt(45),
    issued: false,
    course_lines: [
      courseLine("CEN101", "Engineering Drawing",      2, 10, 12, "F", 0.0, "2022/2023", "FIRST"),
      courseLine("CEN201", "Digital Logic Design",     3, 12, 15, "F", 0.0, "2023/2024", "FIRST")
    ]
  }
]);

print("---- transcript_documents seed count: " + db.transcript_documents.countDocuments() + " ----");

// =====================================================================
// PIPELINE 1 -- count audit events per event_type
// =====================================================================
print("\n---- Pipeline 1: events per event_type ----");
db.result_audit_log.aggregate([
  { $group: {
      _id: "$event_type",
      count: { $sum: NumberInt(1) },
      distinct_actors: { $addToSet: "$actor" }
  }},
  { $sort: { _id: 1 } }
]).forEach(doc => printjson(doc));

// =====================================================================
// PIPELINE 2 -- average CGPA per graduation_class
// =====================================================================
print("\n---- Pipeline 2: average CGPA per graduation_class ----");
db.transcript_documents.aggregate([
  { $group: {
      _id: "$graduation_class",
      students: { $sum: NumberInt(1) },
      avg_cgpa: { $avg: "$cgpa" },
      min_cgpa: { $min: "$cgpa" },
      max_cgpa: { $max: "$cgpa" }
  }},
  { $sort: { avg_cgpa: -1 } }
]).forEach(doc => printjson(doc));

// =====================================================================
// PIPELINE 3 -- top students by CGPA with their credit load
// =====================================================================
print("\n---- Pipeline 3: top 5 students by CGPA ----");
db.transcript_documents.aggregate([
  { $project: {
      _id: 0,
      matric_no: 1,
      student_name: 1,
      programme_code: 1,
      cgpa: 1,
      graduation_class: 1,
      total_credits: 1,
      courses_counted: { $size: "$course_lines" }
  }},
  { $sort: { cgpa: -1 } },
  { $limit: NumberInt(5) }
]).forEach(doc => printjson(doc));

print("\n---- 02_data_and_queries.js done ----");
