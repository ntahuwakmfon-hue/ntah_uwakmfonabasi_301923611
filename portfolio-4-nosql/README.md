# Portfolio 4 — NoSQL (MongoDB 7+)

**Database:** `resultsys` (MongoDB 7+, Unix socket, `mongosh resultsys`)

## What this portfolio does

Stores the **document-oriented** parts of the result system in MongoDB: the audit log of grade-change and approval events, and generated transcript snapshots with embedded course lines. Demonstrates `$jsonSchema` collection validation, three aggregation pipelines, and a 40,000-document bulk insert plus a `COLLSCAN → IXSCAN` index comparison.

## Files

| File | What it does |
| --- | --- |
| `01_setup.js` | Creates `result_audit_log` and `transcript_documents` collections with `$jsonSchema` validators. Uses `enum:[X]` (not `const:X`), `oneOf` for variant schemas, no `if/then/else`, and `additionalProperties:false` with every field listed. Numbers use `bsonType:"int"`/`"double"`/`"long"`. |
| `02_data_and_queries.js` | Seeds five audit events (one per event type plus extras) and five transcript snapshots, then runs three aggregation pipelines. |
| `03_bulk_and_index_demo.js` | Inserts 40,000 documents into `bulk_results` with `insertMany` in batches of 1,000, then runs the same `{matric_no, course_code}` query BEFORE (forced `COLLSCAN` via `hint({$natural:1})`) and AFTER (compound index). Prints Stage / Docs / Time before and after. `dropIndex` is wrapped in `try/catch`. |

## Why document storage fits these two cases

- **`result_audit_log`** stores heterogeneous events: a grade-change event carries `old_grade`/`new_grade`/`old_total_score`/`new_total_score`/`reason`, while a batch-published event carries `batch_id`/`course_code`/`semester_session`/`approved_count`. A relational design would need a wide table with many NULL columns or several joined tables; a document with a per-event-type `detail` sub-object is the natural shape. The `oneOf` in the `$jsonSchema` keeps the variant shapes validated.
- **`transcript_documents`** stores an immutable snapshot of a student's transcript at issue time, with course lines embedded. Issuing a transcript becomes a single read of one document rather than a multi-table join — exactly what a transcript office needs when responding to verification requests from NYSC, employers, or other universities.

## `$jsonSchema` design notes (rules from the rubric)

- `db = db.getSiblingDB("resultsys")` is used instead of `use resultsys`.
- Where a single fixed value would naturally use `const:X`, we use `enum:[X]` (e.g. `event_type: { enum: ["GRADE_CHANGE"] }` in the `oneOf` branches).
- No `if/then/else` conditional schemas; variant shapes are expressed with `oneOf`.
- Where `additionalProperties:false` is set, **every** field including `_id` is listed in `properties`.
- Numeric BSON types are explicit: `int` (Int32) for `credit_units`, `approved_count`, `total_credits`; `double` for scores and CGPA; `long` for `result_id` and `batch_id`.

## How to run

```bash
mongosh resultsys 01_setup.js
mongosh resultsys 02_data_and_queries.js
mongosh resultsys 03_bulk_and_index_demo.js
```

## Expected output of the bulk/index demo

After `03_bulk_and_index_demo.js` runs, the script prints a comparison table like this:

```
                  BEFORE              AFTER
Stage   : COLLSCAN             FETCH
Docs    : 40000                <small number, e.g. 200>
Time ms : <larger>             <smaller>
```

(BEFORE is `COLLSCAN` because `hint({$natural:1})` forces a collection scan of all 40,000 docs; AFTER is `FETCH` with input stage `IXSCAN` because the compound index `{matric_no:1, course_code:1}` lets the planner seek directly to the matching docs.) Paste the real numbers below:

```
[paste real output here]
```
