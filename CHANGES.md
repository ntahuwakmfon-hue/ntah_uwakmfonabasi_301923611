# CHANGES (testing and fixes)

The project was run end to end in a GitHub-Codespaces-like environment (PostgreSQL 16, MongoDB, non-root user). These problems were found and fixed.

| # | File | Problem when run | Fix | Tested result |
|---|------|------------------|-----|---------------|
| 1 | portfolio-1/03_seed_data.sql | Student INSERT had 10 columns but 9 values (state_of_origin missing) | Added state_of_origin to all 6 student rows | Seed loads |
| 2 | portfolio-1/04_bulk_data.sql and 03_seed_data.sql | Inserted PUBLISHED results into PUBLISHED batches; trigger rejects this | Results inside published batches are now APPROVED (the state the trigger requires) | 60,000 bulk rows load |
| 3 | portfolio-1/01_schema.sql (trg_compute_grade) | A score update with an old grade stored was rejected as a "typed grade" | Only a newly typed grade is rejected; on score updates the grade is recomputed | Race demos run |
| 4 | portfolio-2/01_queries.sql, 02_explain_analyze.sql | sem.start_date in ORDER BY but not in GROUP BY | Added sem.start_date to GROUP BY (3 places) | All queries run |
| 5 | portfolio-3/01_transactions.sql | psql :variable used inside DO blocks (syntax error, then aborted transaction) | Passed the id through set_config / current_setting | Transaction demos run; the "intentional abort" message is by design |
| 6 | runall.sh | Failures inside a step were hidden (set -e ignored under ||) | Step failures now stop the run | Clean run, ends with ALL DONE |
| 7 | portfolio-5 | No working replica demo | Added 02_replica_setup.sh and 03_replica_tests.sql | Replica streams; write on replica is rejected (expected message) |

Expected messages that are not errors: "intentional abort for demo 2", "deadlock detected" (Part 6 demo), "cannot execute INSERT in a read-only transaction" (proves the replica is read-only).
