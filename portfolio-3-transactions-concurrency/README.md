# Portfolio 3 — Transactions and Concurrency

**Database:** `resultsys` (PostgreSQL 16)

## What this portfolio does

Three transaction-pattern demos in `01_transactions.sql` and a six-part concurrency demonstration in `race_demos.py` that reproduces a real write-skew race in the result-approval workflow, then fixes it with SERIALIZABLE isolation plus an application retry loop on SQLSTATE 40001.

## Files

| File | What it does |
| --- | --- |
| `01_transactions.sql` | Three patterns: a committed result-posting transaction; a rolled-back transaction (one bad row aborts the lot); a SAVEPOINT recovery where a batch upload of scores has one bad row skipped and the rest still commit. |
| `race_demos.py` | Six labelled concurrency parts, each with its own demo batch (in the future semester 2025/2026 FIRST) and demo students (`ICU/DEMO/NNNN`). The script cleans up its own rows at the end. |

## The race scenario (the one the rubric specifies)

Rule: **a result batch may be published only if every result in it is APPROVED.**

- Session A approves the last pending result and publishes the batch.
- Session B at the same time inserts a new PENDING result into the same batch.

Under **REPEATABLE READ**, A's snapshot was taken before B's insert; A's publish trigger counts 0 pending and lets the publish through. Both transactions commit. The published batch now contains B's unapproved result — a **write skew**.

Under **SERIALIZABLE**, Postgres detects the read/write dependency at A's COMMIT and aborts it with **SQLSTATE 40001**. The application retry loop re-runs A's transaction; the new snapshot sees B's PENDING row, A approves it too, then publishes. No unapproved result leaks into the published batch.

This portfolio deliberately does **not** use advisory locks, `SKIP LOCKED`, or an atomic `UPDATE` as the main fix. `SELECT ... FOR UPDATE` appears only as the labelled comparison in Part 4.

## The six parts of `race_demos.py`

| Part | What it shows |
| --- | --- |
| 1 | The bug under REPEATABLE READ — A publishes and B inserts concurrently; the published batch ends up containing B's PENDING result. |
| 2 | Where a trigger constraint applies: A publishes and **commits first**; B's later INSERT of a PENDING row into the now-PUBLISHED batch is blocked by `trg_check_result_batch_consistency`. |
| 3 | The SERIALIZABLE fix: both sessions SERIALIZABLE; A gets SQLSTATE 40001 on first COMMIT, the retry loop re-runs the transaction and succeeds. |
| 4 | Comparison only: `SELECT ... FOR UPDATE` on the `result_batch` row serialises the two officers (B blocks until A commits). Heavier than needed; kept for comparison. |
| 5 | READ COMMITTED vs REPEATABLE READ: RC re-reads per statement and sees B's newly committed row; RR's snapshot is frozen at BEGIN and does not. This is *why* the write-skew bug exists. |
| 6 | Deadlock (SQLSTATE 40P01): two officers updating the same two results in opposite order; then the fixed-order version (both update in ascending `result_id` order). |

The script uses `psycopg2` with two real sessions run in Python threads. Coordination between threads uses `threading.Event` so no hand-pasted `pg_sleep` is needed. The script creates and deletes its own demo rows.

## How to run

```bash
# 1. Transactions demo (pure SQL)
psql -d resultsys -v ON_ERROR_STOP=1 -f 01_transactions.sql

# 2. Concurrency demo
pip install psycopg2-binary    # if not already installed
python3 race_demos.py
```

## Expected output

Each part prints a banner, the outcome of each session, the final batch status and the count of PENDING rows in the batch. Part 1 prints `BUG REPRODUCED`; Part 3 prints `FIX CONFIRMED`; Part 6 prints the deadlock SQLSTATE for one session and "committed" for both in the fixed-order version. Paste the real output below:

```
[paste real output here]
```

## Why SERIALIZABLE + retry is the right fix here

- **Triggers alone cannot close the hole under REPEATABLE READ** (Part 2 only works when A commits before B acts). The trigger's SELECT uses the transaction's snapshot and cannot see B's uncommitted or just-committed row.
- **`SELECT ... FOR UPDATE`** (Part 4) works but is heavier: it blocks B even when B is doing something that would not actually conflict, and it requires the application to remember to take the lock in every code path.
- **SERIALIZABLE** lets Postgres track the dependencies and only abort when there is an actual conflict (SQLSTATE 40001). The retry loop pays the cost only when needed. This is the textbook remedy for write-skew and is the one this portfolio uses.
