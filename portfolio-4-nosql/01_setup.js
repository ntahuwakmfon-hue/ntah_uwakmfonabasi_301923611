// 01_setup.js
// Purpose: Create MongoDB collections with $jsonSchema validation for the
// result-processing audit log and transcript snapshot store.
// Rules followed:
//   - db = db.getSiblingDB("resultsys")   (not `use resultsys`)
//   - enum:[X] is used instead of const:X
//   - no if/then/else; oneOf is used for variant schemas
//   - additionalProperties:false lists _id and EVERY field
//   - numbers use bsonType "int" (Int32) or "double" (Double) or "long"
// Run with: mongosh resultsys 01_setup.js

db = db.getSiblingDB("resultsys");

// ---------------------------------------------------------------------
// Drop existing collections so the script is idempotent.
// ---------------------------------------------------------------------
try { db.result_audit_log.drop(); } catch (e) { print("drop result_audit_log: " + e.message); }
try { db.transcript_documents.drop(); } catch (e) { print("drop transcript_documents: " + e.message); }

// =====================================================================
// Collection 1: result_audit_log
// Flexible event log: GRADE_CHANGE / BATCH_PUBLISHED / RESULT_APPROVED
// Each event type has its own `detail` shape, validated with oneOf.
// additionalProperties:false on every object schema -> every field listed.
// =====================================================================
db.createCollection("result_audit_log", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Ibom Crown result audit event",
      required: ["_id", "event_type", "result_id", "matric_no", "occurred_at", "actor", "detail"],
      properties: {
        _id:            { bsonType: "objectId" },
        event_type:     { bsonType: "string" },
        result_id:      { bsonType: "long" },
        matric_no:      { bsonType: "string" },
        course_code:    { bsonType: "string" },
        occurred_at:    { bsonType: "date" },
        actor:          { bsonType: "string" }
      },
      // Variant schemas: one and only one branch must match.
      oneOf: [
        {
          properties: {
            event_type: { enum: ["GRADE_CHANGE"] },          // enum:[X], not const:X
            detail: {
              bsonType: "object",
              required: ["_id", "old_grade", "new_grade", "reason"],
              properties: {
                _id:              { bsonType: "objectId" },
                old_grade:        { bsonType: "string" },
                new_grade:        { bsonType: "string" },
                old_total_score:  { bsonType: "double" },
                new_total_score:  { bsonType: "double" },
                reason:           { bsonType: "string" },
                changed_in_tx:    { bsonType: "date" }
              },
              additionalProperties: false
            }
          }
        },
        {
          properties: {
            event_type: { enum: ["BATCH_PUBLISHED"] },
            detail: {
              bsonType: "object",
              required: ["_id", "batch_id", "course_code", "semester_session", "approved_count"],
              properties: {
                _id:                { bsonType: "objectId" },
                batch_id:           { bsonType: "long" },
                course_code:        { bsonType: "string" },
                semester_session:   { bsonType: "string" },
                semester_term:      { bsonType: "string" },
                approved_count:     { bsonType: "int" },     // Int32
                approved_by_senate: { bsonType: "bool" }
              },
              additionalProperties: false
            }
          }
        },
        {
          properties: {
            event_type: { enum: ["RESULT_APPROVED"] },
            detail: {
              bsonType: "object",
              required: ["_id", "approver", "previous_status", "new_status"],
              properties: {
                _id:              { bsonType: "objectId" },
                approver:         { bsonType: "string" },
                previous_status:  { bsonType: "string" },
                new_status:       { bsonType: "string" },
                moderation_notes: { bsonType: "string" }
              },
              additionalProperties: false
            }
          }
        }
      ]
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// =====================================================================
// Collection 2: transcript_documents
// Generated transcript snapshots with embedded course lines.
// additionalProperties:false -> every field listed.
// =====================================================================
db.createCollection("transcript_documents", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      title: "Ibom Crown transcript snapshot",
      required: ["_id", "transcript_id", "matric_no", "student_name", "programme",
                 "programme_code", "generated_at", "cgpa", "graduation_class",
                 "academic_standing", "total_credits", "course_lines", "issued"],
      properties: {
        _id:                { bsonType: "objectId" },
        transcript_id:      { bsonType: "string" },         // e.g. "TR/2025/0001"
        matric_no:          { bsonType: "string" },
        student_name:       { bsonType: "string" },
        programme:          { bsonType: "string" },
        programme_code:     { bsonType: "string" },
        generated_at:       { bsonType: "date" },
        cgpa:               { bsonType: "double" },          // Double
        graduation_class:   { bsonType: "string" },
        academic_standing:  { bsonType: "string" },
        total_credits:      { bsonType: "int" },             // Int32
        issued:             { bsonType: "bool" },
        course_lines: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["_id", "course_code", "course_title", "credit_units",
                       "ca_score", "exam_score", "total_score", "grade", "grade_point",
                       "semester_session", "semester_term"],
            properties: {
              _id:               { bsonType: "objectId" },
              course_code:       { bsonType: "string" },
              course_title:      { bsonType: "string" },
              credit_units:      { bsonType: "int" },        // Int32
              ca_score:          { bsonType: "double" },     // Double
              exam_score:        { bsonType: "double" },     // Double
              total_score:       { bsonType: "double" },     // Double
              grade:             { bsonType: "string" },
              grade_point:       { bsonType: "double" },     // Double
              semester_session:  { bsonType: "string" },
              semester_term:     { bsonType: "string" }
            },
            additionalProperties: false
          }
        }
      },
      // Use oneOf to constrain graduation_class + academic_standing to a
      // consistent pair.
      oneOf: [
        {
          properties: {
            graduation_class:  { enum: ["First Class"] },
            academic_standing: { enum: ["Good Standing"] }
          }
        },
        {
          properties: {
            graduation_class:  { enum: ["Second Class Upper"] },
            academic_standing: { enum: ["Good Standing"] }
          }
        },
        {
          properties: {
            graduation_class:  { enum: ["Second Class Lower"] },
            academic_standing: { enum: ["Good Standing"] }
          }
        },
        {
          properties: {
            graduation_class:  { enum: ["Third Class"] },
            academic_standing: { enum: ["Good Standing"] }
          }
        },
        {
          properties: {
            graduation_class:  { enum: ["Pass"] },
            academic_standing: { enum: ["Probation"] }
          }
        },
        {
          properties: {
            graduation_class:  { enum: ["Fail"] },
            academic_standing: { enum: ["Withdrawal"] }
          }
        }
      ],
      additionalProperties: false
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

// =====================================================================
// Drop the bulk-demo collection if it exists (used by 03_bulk_and_index_demo.js)
// =====================================================================
try { db.bulk_results.drop(); } catch (e) { print("drop bulk_results: " + e.message); }

// Summary
print("---- collections in resultsys after setup ----");
db.getCollectionNames().forEach(n => print("  " + n));
