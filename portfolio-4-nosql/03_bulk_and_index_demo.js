// 03_bulk_and_index_demo.js
// Purpose: Insert 40,000 documents into the bulk_results collection with
// insertMany in batches, then run the SAME query twice:
//   BEFORE the compound index  -- hint({$natural:1}) forces a COLLSCAN
//   AFTER  the compound index  -- the planner uses IXSCAN + FETCH
// Prints Stage / Docs / Time BEFORE and AFTER.
// Run with: mongosh resultsys 03_bulk_and_index_demo.js

db = db.getSiblingDB("resultsys");

// ---------------------------------------------------------------------
// 1. Reset the bulk collection.
// ---------------------------------------------------------------------
try { db.bulk_results.drop(); } catch (e) { print("drop bulk_results: " + e.message); }
db.createCollection("bulk_results");

// ---------------------------------------------------------------------
// 2. Build 40,000 documents and insert them in batches of 1,000.
//    The query target is matric_no "ICU/2024/00100" + course_code "CSC101".
// ---------------------------------------------------------------------
const TOTAL       = 40000;
const BATCH_SIZE  = 1000;
const TARGET_MATRIC = "ICU/2024/00100";
const TARGET_COURSE = "CSC101";

const COURSES = ["CSC101","CSC201","CSC202","MTH101","MTH201","ECN101","ACC101","CEN101"];
const GRADES  = [["A",5.0],["B",4.0],["C",3.0],["D",2.0],["E",1.0],["F",0.0]];

let inserted = 0;
let batch = [];
for (let i = 0; i < TOTAL; i++) {
  // Make sure the target (matric_no, course_code) appears several times
  // so the AFTER plan returns a non-trivial number of docs.
  let matric, course;
  if (i % 200 === 0) {
    matric = TARGET_MATRIC;
    course = TARGET_COURSE;
  } else {
    const snum = (i % 2000) + 1;
    matric = "ICU/2024/" + snum.toString().padStart(5, "0");
    course = COURSES[i % COURSES.length];
  }
  const ca  = (i % 30) + 8;
  const ex  = (i % 50) + 5;
  const tot = ca + ex;
  const gIdx = Math.min(5, Math.floor(tot / 17));   // 0..5
  batch.push({
    matric_no: matric,
    course_code: course,
    semester_session: "2024/2025",
    ca_score: Double(ca),
    exam_score: Double(ex),
    total_score: Double(tot),
    grade: GRADES[gIdx][0],
    grade_point: Double(GRADES[gIdx][1]),
    created_at: new Date(Date.now() - i * 1000)
  });

  if (batch.length === BATCH_SIZE) {
    db.bulk_results.insertMany(batch, { ordered: false });
    inserted += batch.length;
    batch = [];
  }
}
if (batch.length > 0) {
  db.bulk_results.insertMany(batch, { ordered: false });
  inserted += batch.length;
}
print("---- inserted " + inserted + " documents into bulk_results ----");
print("---- collection count: " + db.bulk_results.countDocuments() + " ----");

// The query both BEFORE and AFTER will run.
const query = { matric_no: TARGET_MATRIC, course_code: TARGET_COURSE };

// ---------------------------------------------------------------------
// Helper: extract Stage / Docs / Time from an executionStats plan.
// ---------------------------------------------------------------------
function summarise(plan, label) {
  const st = plan && plan.executionStats;
  if (!st) {
    print(label + ": no executionStats in plan");
    return { stage: "n/a", docs: -1, ms: -1 };
  }
  // Walk the stages to find the root stage name (COLLSCAN / IXSCAN / FETCH ...).
  let stage = st.executionStages && st.executionStages.stage;
  // For IXSCAN, the root is usually FETCH with inputStage IXSCAN -- report both.
  let innerStage = st.executionStages && st.executionStages.inputStage
                    && st.executionStages.inputStage.stage;
  const docs = st.totalDocsExamined;
  const ms   = st.executionTimeMillis;
  print(label
        + "  stage=" + stage + (innerStage ? " -> " + innerStage : "")
        + "  docsExamined=" + docs
        + "  nReturned=" + st.nReturned
        + "  timeMs=" + ms);
  return { stage: stage, docs: docs, ms: ms };
}

// ---------------------------------------------------------------------
// 3. BEFORE: force a COLLSCAN with hint({$natural:1}).
//    dropIndex is wrapped in try/catch in case it does not exist yet.
// ---------------------------------------------------------------------
try { db.bulk_results.dropIndex({ matric_no: 1, course_code: 1 }); }
catch (e) { print("dropIndex before-demo (no-op if absent): " + e.message); }

print("\n==== BEFORE compound index (hint {$natural:1}) ====");
const beforePlan = db.bulk_results
  .find(query)
  .hint({ $natural: 1 })
  .explain("executionStats");
const before = summarise(beforePlan, "BEFORE");

// ---------------------------------------------------------------------
// 4. Create the compound index.
// ---------------------------------------------------------------------
db.bulk_results.createIndex({ matric_no: 1, course_code: 1 },
                            { name: "idx_matric_course" });
print("---- created compound index idx_matric_course ----");

// ---------------------------------------------------------------------
// 5. AFTER: re-run the same query; the planner should use IXSCAN + FETCH.
// ---------------------------------------------------------------------
print("\n==== AFTER compound index (planner chooses IXSCAN) ====");
const afterPlan = db.bulk_results
  .find(query)
  .explain("executionStats");
const after = summarise(afterPlan, "AFTER ");

// ---------------------------------------------------------------------
// 6. Print the comparison table.
// ---------------------------------------------------------------------
print("\n==== Comparison ====");
print("                  BEFORE              AFTER");
print("Stage   : " + before.stage + "             " + after.stage);
print("Docs    : " + before.docs  + "             " + after.docs);
print("Time ms : " + before.ms    + "             " + after.ms);

// ---------------------------------------------------------------------
// 7. Leave the collection and index in place so the student can re-run
//    EXPLAIN by hand if they wish. (Drop is wrapped in try/catch above.)
// ---------------------------------------------------------------------
print("\n---- done.  Documents in bulk_results: "
      + db.bulk_results.countDocuments() + " ----");
