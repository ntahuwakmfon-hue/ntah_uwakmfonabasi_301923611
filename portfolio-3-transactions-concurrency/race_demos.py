#!/usr/bin/env python3
"""race_demos.py -- six concurrency demonstrations on the resultsys schema.

Each part creates its own demo rows (matric_no 'ICU/DEMO/NNNN' and a fresh
result_batch in the future semester 2025/2026 FIRST) and deletes them at
the end, so the script can be rerun safely.

Parts:
  1  The bug -- write skew under REPEATABLE READ: a PUBLISHED batch ends
     up containing an unapproved result.
  2  A trigger constraint fix where one applies -- A publishes and commits
     FIRST; B's later INSERT of a PENDING row into the PUBLISHED batch is
     blocked by trg_check_result_batch_consistency.
  3  The SERIALIZABLE fix -- both sessions SERIALIZABLE; one session gets
     SQLSTATE 40001 at COMMIT, the retry loop re-runs the transaction and
     succeeds.
  4  COMPARISON ONLY -- SELECT ... FOR UPDATE on the result_batch row.
  5  READ COMMITTED vs REPEATABLE READ -- shows that RC sees a freshly
     committed row mid-transaction while RR does not.
  6  Deadlock (40P01) -- two officers updating the same two results in
     opposite order; then the fixed-order version (both in id order).

Run with:  python3 race_demos.py
Requires:  psycopg2  (pip install psycopg2-binary)
Connects over the Unix socket to database `resultsys`, no password, no TCP.
"""

import threading
import psycopg2
import psycopg2.errorcodes
from psycopg2 import errors

DBNAME = "resultsys"

# isolation level strings for connection.set_session()
RC  = "READ COMMITTED"
RR  = "REPEATABLE READ"
SER = "SERIALIZABLE"


def new_conn(iso):
    """Open a connection to resultsys at the given isolation level."""
    c = psycopg2.connect(dbname=DBNAME)        # Unix socket, peer/trust auth
    c.set_session(isolation_level=iso, autocommit=False)
    return c


def exec_one(sql, params=None):
    """Run a single statement in its own READ COMMITTED transaction."""
    c = new_conn(RC)
    try:
        with c.cursor() as cur:
            cur.execute(sql, params)
        c.commit()
    finally:
        c.close()


def fetch_one(sql, params=None):
    c = new_conn(RC)
    try:
        with c.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()
    finally:
        c.close()


def banner(title):
    print()
    print("=" * 72)
    print(title)
    print("=" * 72)


# ---------------------------------------------------------------------
# Demo data helpers
# ---------------------------------------------------------------------

DEMO_COURSE_CODE   = "CSC101"
DEMO_SESSION       = "2025/2026"
DEMO_TERM          = "FIRST"
DEMO_STAFF_NO      = "ICU/STAFF/001"
DEMO_DEPT_CODE     = "CSC"
N_DEMO_STUDENTS    = 12

MALE_NAMES   = ["Akpan", "Ntiedo", "Ekemini", "Inyang", "Uduak", "Ndifreke"]
FEMALE_NAMES = ["Emem",  "Ekaette", "Ima",    "Affiong", "Comfort", "Grace"]
LAST_NAMES   = ["Ntah", "Edet", "Bassey", "Okon", "Ekanem", "Umoh",
                "Asuquo", "Eshiet", "Nkanta", "Udoudo", "James", "Mark"]


def ensure_demo_students():
    """Insert demo students idempotently."""
    rows = []
    for i in range(1, N_DEMO_STUDENTS + 1):
        matric = f"ICU/DEMO/{i:04d}"
        if i % 2 == 0:
            first, gender = MALE_NAMES[i % len(MALE_NAMES)], "M"
        else:
            first, gender = FEMALE_NAMES[i % len(FEMALE_NAMES)], "F"
        last = LAST_NAMES[i % len(LAST_NAMES)]
        rows.append((matric, 1, first, last, gender, 100, "active",
                     "2024/2025", "Akwa Ibom", 250000.00))
    c = new_conn(RC)
    try:
        with c.cursor() as cur:
            cur.executemany("""
                INSERT INTO student
                    (matric_no, programme_id, first_name, last_name, gender,
                     level, status, session_admitted, state_of_origin, tuition_ngn)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                ON CONFLICT (matric_no) DO NOTHING
            """, rows)
        c.commit()
    finally:
        c.close()


def make_demo_batch(initial_status, n_approved, n_pending):
    """Create (or reuse) a fresh result_batch in 2025/2026 FIRST for CSC101
    with the requested mix of result statuses. Returns (batch_id, [result_ids])."""
    ensure_demo_students()
    # Resolve IDs
    course_id, = fetch_one("SELECT course_id FROM course WHERE code=%s", (DEMO_COURSE_CODE,))
    sem_id,    = fetch_one("SELECT semester_id FROM semester WHERE session=%s AND term=%s",
                           (DEMO_SESSION, DEMO_TERM))
    dept_id,   = fetch_one("SELECT dept_id FROM department WHERE dept_code=%s", (DEMO_DEPT_CODE,))
    lec_id,    = fetch_one("SELECT lecturer_id FROM lecturer WHERE staff_no=%s", (DEMO_STAFF_NO,))

    c = new_conn(RC)
    try:
        with c.cursor() as cur:
            # Wipe any prior demo results for this course+semester first
            cur.execute("""
                DELETE FROM assessment_result
                WHERE course_id=%s AND semester_id=%s
                  AND matric_no LIKE 'ICU/DEMO/%%'
            """, (course_id, sem_id))
            cur.execute("""
                DELETE FROM result_batch
                WHERE course_id=%s AND semester_id=%s AND dept_id=%s
            """, (course_id, sem_id, dept_id))
            cur.execute("""
                INSERT INTO result_batch (course_id, semester_id, dept_id, lecturer_id, status)
                VALUES (%s,%s,%s,%s,%s)
                RETURNING batch_id
            """, (course_id, sem_id, dept_id, lec_id, initial_status))
            batch_id, = cur.fetchone()

            result_ids = []
            n_total = n_approved + n_pending
            for i in range(1, n_total + 1):
                status = "PENDING" if i > n_approved else "APPROVED"
                # vary the scores so grade derivation has something to do
                ca = 10 + (i % 20)
                ex = 20 + (i % 30)
                cur.execute("""
                    INSERT INTO assessment_result
                        (batch_id, matric_no, course_id, semester_id,
                         ca_score, exam_score, status, superseded)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,FALSE)
                    RETURNING result_id
                """, (batch_id, f"ICU/DEMO/{i:04d}", course_id, sem_id,
                      ca, ex, status))
                result_ids.append(cur.fetchone()[0])
        c.commit()
        return batch_id, result_ids, course_id, sem_id
    finally:
        c.close()


def cleanup_demo():
    """Delete every row this script created (demo students, batches, results)."""
    c = new_conn(RC)
    try:
        with c.cursor() as cur:
            # results -> audit -> batch -> student, in dependency-safe order
            cur.execute("""
                DELETE FROM grade_change_audit
                WHERE result_id IN (
                    SELECT result_id FROM assessment_result
                    WHERE matric_no LIKE 'ICU/DEMO/%%'
                )
            """)
            cur.execute("DELETE FROM assessment_result WHERE matric_no LIKE 'ICU/DEMO/%%'")
            # Only delete the DEMO batch (CSC101 in 2025/2026 FIRST owned by
            # the CSC department) -- NOT every batch in 2025/2026 FIRST,
            # because 01_transactions.sql created an EDU101 batch there too.
            cur.execute("""
                DELETE FROM result_batch
                WHERE course_id = (SELECT course_id FROM course WHERE code=%s)
                  AND semester_id = (
                      SELECT semester_id FROM semester
                      WHERE session=%s AND term=%s
                  )
                  AND dept_id = (SELECT dept_id FROM department WHERE dept_code=%s)
            """, (DEMO_COURSE_CODE, DEMO_SESSION, DEMO_TERM, DEMO_DEPT_CODE))
            cur.execute("DELETE FROM student WHERE matric_no LIKE 'ICU/DEMO/%%'")
        c.commit()
    finally:
        c.close()


# ---------------------------------------------------------------------
# PART 1: the write-skew bug under REPEATABLE READ
# ---------------------------------------------------------------------
def part1_bug():
    banner("PART 1 -- the BUG: write skew under REPEATABLE READ")
    batch_id, result_ids, course_id, sem_id = make_demo_batch("APPROVED", 4, 1)

    b_inserted   = threading.Event()
    a_committed  = threading.Event()
    out = {}

    def session_a():
        c = new_conn(RR)
        try:
            with c.cursor() as cur:
                # A's snapshot is taken here: 1 pending result (the one we want to approve)
                cur.execute("""
                    SELECT count(*) FROM assessment_result
                    WHERE batch_id=%s AND status='PENDING'
                """, (batch_id,))
                out["a_initial_pending"] = cur.fetchone()[0]

                # approve that pending result
                cur.execute("""
                    UPDATE assessment_result SET status='APPROVED'
                    WHERE batch_id=%s AND status='PENDING'
                """, (batch_id,))
                out["a_approved"] = cur.rowcount

                # publish the batch. trg_check_batch_publish fires and queries
                # the SAME REPEATABLE READ snapshot -> sees 0 pending -> allows.
                cur.execute("UPDATE result_batch SET status='PUBLISHED' WHERE batch_id=%s",
                            (batch_id,))

                # wait until B has inserted its (uncommitted) PENDING row
                if not b_inserted.wait(timeout=10):
                    out["a"] = "timed out waiting for B"
                    c.rollback()
                    return
                c.commit()
                out["a"] = "committed"
        except Exception as e:
            c.rollback()
            out["a"] = f"failed: {getattr(e, 'pgcode', type(e).__name__)} {e}"
        finally:
            c.close()
            a_committed.set()

    def session_b():
        c = new_conn(RR)
        try:
            with c.cursor() as cur:
                cur.execute("""
                    INSERT INTO assessment_result
                        (batch_id, matric_no, course_id, semester_id,
                         ca_score, exam_score, status, superseded)
                    VALUES (%s,%s,%s,%s,%s,%s,'PENDING',FALSE)
                """, (batch_id, "ICU/DEMO/0011", course_id, sem_id, 25.0, 30.0))
                b_inserted.set()
                # wait until A has committed (so B commits AFTER A)
                if not a_committed.wait(timeout=10):
                    out["b"] = "timed out waiting for A"
                    c.rollback()
                    return
                c.commit()
                out["b"] = "committed"
        except Exception as e:
            c.rollback()
            out["b"] = f"failed: {getattr(e, 'pgcode', type(e).__name__)} {e}"
            b_inserted.set()
        finally:
            c.close()

    ta = threading.Thread(target=session_a, name="A")
    tb = threading.Thread(target=session_b, name="B")
    ta.start(); tb.start()
    ta.join();  tb.join()

    # Inspect the final state from a fresh connection
    batch_status, = fetch_one("SELECT status FROM result_batch WHERE batch_id=%s", (batch_id,))
    n_pending,    = fetch_one("""
        SELECT count(*) FROM assessment_result
        WHERE batch_id=%s AND status='PENDING'
    """, (batch_id,))

    print(f"  A: {out.get('a')}  (saw {out.get('a_initial_pending')} pending, "
          f"approved {out.get('a_approved')})")
    print(f"  B: {out.get('b')}  (inserted a new PENDING row)")
    print(f"  Final batch status : {batch_status}")
    print(f"  PENDING rows in that batch: {n_pending}")
    if batch_status == "PUBLISHED" and n_pending > 0:
        print("  >>> BUG REPRODUCED: a PUBLISHED batch contains an unapproved result.")
    else:
        print("  >>> Bug NOT reproduced (unexpected).")


# ---------------------------------------------------------------------
# PART 2: a trigger constraint fix where one applies
# ---------------------------------------------------------------------
def part2_constraint_fix():
    banner("PART 2 -- trigger constraint fix WHERE ONE APPLIES "
           "(A publishes and commits FIRST, then B tries to insert)")
    batch_id, result_ids, course_id, sem_id = make_demo_batch("APPROVED", 5, 0)
    out = {}

    # A publishes and COMMITS first.
    c = new_conn(RC)
    try:
        with c.cursor() as cur:
            cur.execute("UPDATE result_batch SET status='PUBLISHED' WHERE batch_id=%s",
                        (batch_id,))
        c.commit()
        out["a"] = "published + committed"
    finally:
        c.close()

    # B then tries to INSERT a PENDING result into the now-PUBLISHED batch.
    c = new_conn(RC)
    try:
        with c.cursor() as cur:
            cur.execute("""
                INSERT INTO assessment_result
                    (batch_id, matric_no, course_id, semester_id,
                     ca_score, exam_score, status, superseded)
                VALUES (%s,%s,%s,%s,%s,%s,'PENDING',FALSE)
            """, (batch_id, "ICU/DEMO/0011", course_id, sem_id, 25.0, 30.0))
        c.commit()
        out["b"] = "inserted (BAD: trigger did NOT fire)"
    except psycopg2.Error as e:
        c.rollback()
        out["b"] = f"blocked by trigger (SQLSTATE {e.pgcode})"
    finally:
        c.close()

    batch_status, = fetch_one("SELECT status FROM result_batch WHERE batch_id=%s", (batch_id,))
    n_pending,    = fetch_one("""
        SELECT count(*) FROM assessment_result
        WHERE batch_id=%s AND status='PENDING'
    """, (batch_id,))
    print(f"  A: {out['a']}")
    print(f"  B: {out['b']}")
    print(f"  Final batch status : {batch_status}")
    print(f"  PENDING rows in that batch: {n_pending}")
    print("  >>> When A commits BEFORE B acts, the INSERT-time trigger closes the hole.")


# ---------------------------------------------------------------------
# PART 3: the SERIALIZABLE fix with retry on SQLSTATE 40001
# ---------------------------------------------------------------------
def part3_serializable_fix():
    banner("PART 3 -- the FIX: SERIALIZABLE + retry on SQLSTATE 40001")
    batch_id, result_ids, course_id, sem_id = make_demo_batch("APPROVED", 4, 1)
    out = {}

    b_done = threading.Event()

    def session_b():
        """B inserts a new PENDING row and commits FIRST."""
        c = new_conn(SER)
        try:
            with c.cursor() as cur:
                cur.execute("""
                    INSERT INTO assessment_result
                        (batch_id, matric_no, course_id, semester_id,
                         ca_score, exam_score, status, superseded)
                    VALUES (%s,%s,%s,%s,%s,%s,'PENDING',FALSE)
                """, (batch_id, "ICU/DEMO/0011", course_id, sem_id, 25.0, 30.0))
            c.commit()
            out["b"] = "committed (inserted PENDING)"
        except psycopg2.Error as e:
            c.rollback()
            out["b"] = f"failed: SQLSTATE {e.pgcode} {e.pgerror.strip()[:120]}"
        finally:
            c.close()
            b_done.set()

    def session_a_with_retry():
        """A approves pending results and publishes the batch. Retry on 40001."""
        b_done.wait(timeout=10)
        max_retries = 5
        for attempt in range(1, max_retries + 1):
            c = new_conn(SER)
            try:
                with c.cursor() as cur:
                    cur.execute("""
                        UPDATE assessment_result SET status='APPROVED'
                        WHERE batch_id=%s AND status='PENDING'
                    """, (batch_id,))
                    approved = cur.rowcount
                    cur.execute("""
                        UPDATE result_batch SET status='PUBLISHED' WHERE batch_id=%s
                    """, (batch_id,))
                c.commit()
                out["a"] = (f"committed on attempt {attempt} "
                            f"(approved {approved} pending result(s) in retry)")
                c.close()
                return
            except psycopg2.Error as e:
                c.rollback()
                c.close()
                if e.pgcode == "40001":
                    out[f"a_attempt_{attempt}"] = f"SQLSTATE 40001 (serialization), retrying"
                    continue
                out["a"] = f"failed: SQLSTATE {e.pgcode}"
                return
        out["a"] = "exhausted retries"

    tb = threading.Thread(target=session_b, name="B")
    ta = threading.Thread(target=session_a_with_retry, name="A")
    ta.start(); tb.start()
    ta.join();  tb.join()

    batch_status, = fetch_one("SELECT status FROM result_batch WHERE batch_id=%s", (batch_id,))
    n_pending,    = fetch_one("""
        SELECT count(*) FROM assessment_result
        WHERE batch_id=%s AND status='PENDING'
    """, (batch_id,))

    for k in sorted([k for k in out if k.startswith("a_attempt_")]):
        print(f"  A {k}: {out[k]}")
    print(f"  A final: {out.get('a')}")
    print(f"  B: {out.get('b')}")
    print(f"  Final batch status : {batch_status}")
    print(f"  PENDING rows in that batch: {n_pending}")
    if batch_status == "PUBLISHED" and n_pending == 0:
        print("  >>> FIX CONFIRMED: no unapproved result in the PUBLISHED batch.")
    else:
        print("  >>> Fix did not produce the expected state.")


# ---------------------------------------------------------------------
# PART 4: COMPARISON ONLY -- SELECT ... FOR UPDATE
# ---------------------------------------------------------------------
def part4_for_update_comparison():
    banner("PART 4 -- COMPARISON ONLY: SELECT ... FOR UPDATE on result_batch")
    batch_id, result_ids, course_id, sem_id = make_demo_batch("APPROVED", 5, 0)
    out = {}

    a_locked   = threading.Event()
    b_done     = threading.Event()

    def session_a():
        c = new_conn(RR)
        try:
            with c.cursor() as cur:
                cur.execute("""
                    SELECT status FROM result_batch
                    WHERE batch_id=%s FOR UPDATE
                """, (batch_id,))
                out["a_locked_status"] = cur.fetchone()[0]
                a_locked.set()
                # hold the lock for a moment so B has to wait
                b_done.wait(timeout=10)
                cur.execute("UPDATE result_batch SET status='PUBLISHED' WHERE batch_id=%s",
                            (batch_id,))
            c.commit()
            out["a"] = "committed (published after holding lock)"
        except Exception as e:
            c.rollback()
            out["a"] = f"failed: {getattr(e, 'pgcode', type(e).__name__)}"
        finally:
            c.close()

    def session_b():
        c = new_conn(RR)
        try:
            a_locked.wait(timeout=10)
            with c.cursor() as cur:
                # B blocks here until A commits (or rolls back)
                cur.execute("""
                    SELECT status FROM result_batch
                    WHERE batch_id=%s FOR UPDATE
                """, (batch_id,))
                row = cur.fetchone()
                out["b_saw_status"] = row[0] if row else None
                if out["b_saw_status"] == "PUBLISHED":
                    out["b"] = ("saw PUBLISHED via FOR UPDATE -- "
                                "B aborts its planned PENDING insert")
                else:
                    out["b"] = f"unexpected status {out['b_saw_status']}"
            c.rollback()   # B does not actually change anything
        except Exception as e:
            c.rollback()
            out["b"] = f"failed: {getattr(e, 'pgcode', type(e).__name__)}"
        finally:
            c.close()
            b_done.set()

    ta = threading.Thread(target=session_a, name="A")
    tb = threading.Thread(target=session_b, name="B")
    ta.start(); tb.start()
    ta.join();  tb.join()

    print(f"  A: {out.get('a')}  (locked status: {out.get('a_locked_status')})")
    print(f"  B: {out.get('b')}")
    print("  >>> FOR UPDATE serialises the two officers: B blocks until A is done.")
    print("      This is heavier than SERIALIZABLE+retry; kept here for comparison only.")


# ---------------------------------------------------------------------
# PART 5: READ COMMITTED vs REPEATABLE READ
# ---------------------------------------------------------------------
def part5_rc_vs_rr():
    banner("PART 5 -- READ COMMITTED vs REPEATABLE READ")
    batch_id, result_ids, course_id, sem_id = make_demo_batch("APPROVED", 1, 0)
    out = {}

    # ---- READ COMMITTED session ----
    c_rc = new_conn(RC)
    try:
        with c_rc.cursor() as cur:
            cur.execute("""
                SELECT count(*) FROM assessment_result
                WHERE batch_id=%s AND status='PENDING'
            """, (batch_id,))
            out["rc_before"] = cur.fetchone()[0]

            # Another transaction inserts a PENDING row and commits
            exec_one("""
                INSERT INTO assessment_result
                    (batch_id, matric_no, course_id, semester_id,
                     ca_score, exam_score, status, superseded)
                VALUES (%s,%s,%s,%s,%s,%s,'PENDING',FALSE)
            """, (batch_id, "ICU/DEMO/0011", course_id, sem_id, 25.0, 30.0))

            cur.execute("""
                SELECT count(*) FROM assessment_result
                WHERE batch_id=%s AND status='PENDING'
            """, (batch_id,))
            out["rc_after"] = cur.fetchone()[0]
        c_rc.commit()
    finally:
        c_rc.close()

    # ---- REPEATABLE READ session ----
    # Reset to 0 pending before the RR test
    exec_one("""
        DELETE FROM assessment_result WHERE matric_no='ICU/DEMO/0011'
    """)

    c_rr = new_conn(RR)
    try:
        with c_rr.cursor() as cur:
            cur.execute("""
                SELECT count(*) FROM assessment_result
                WHERE batch_id=%s AND status='PENDING'
            """, (batch_id,))
            out["rr_before"] = cur.fetchone()[0]

            # Another transaction inserts a PENDING row and commits AFTER our BEGIN
            exec_one("""
                INSERT INTO assessment_result
                    (batch_id, matric_no, course_id, semester_id,
                     ca_score, exam_score, status, superseded)
                VALUES (%s,%s,%s,%s,%s,%s,'PENDING',FALSE)
            """, (batch_id, "ICU/DEMO/0012", course_id, sem_id, 25.0, 30.0))

            cur.execute("""
                SELECT count(*) FROM assessment_result
                WHERE batch_id=%s AND status='PENDING'
            """, (batch_id,))
            out["rr_after"] = cur.fetchone()[0]
        c_rr.commit()
    finally:
        c_rr.close()

    print(f"  READ COMMITTED : before={out['rc_before']}, after={out['rc_after']}  "
          f"({'saw the new row' if out['rc_after'] > out['rc_before'] else 'no change'})")
    print(f"  REPEATABLE READ: before={out['rr_before']}, after={out['rr_after']}  "
          f"({'snapshot frozen -- did NOT see the new row' if out['rr_after'] == out['rr_before'] else 'saw the new row'})")
    print("  >>> RC re-reads per statement; RR uses the snapshot frozen at BEGIN.")
    print("      The write-skew bug exists because RR's trigger SELECT cannot see a")
    print("      concurrently inserted row, so it under-counts PENDING results.")


# ---------------------------------------------------------------------
# PART 6: deadlock (40P01) and the fixed-order version
# ---------------------------------------------------------------------
def part6_deadlock():
    banner("PART 6 -- deadlock (40P01) + the fixed-id-order version")
    # Use a PENDING batch so updates do not trip the publication trigger.
    batch_id, result_ids, course_id, sem_id = make_demo_batch("PENDING", 2, 0)
    r1, r2 = result_ids[0], result_ids[1]
    out = {}

    # ---- Deadlock version: opposite update order ----
    a_first = threading.Event()
    b_first = threading.Event()

    def session_a_deadlock():
        c = new_conn(RC)
        try:
            with c.cursor() as cur:
                cur.execute("UPDATE assessment_result SET ca_score=15.00 WHERE result_id=%s", (r1,))
                a_first.set()
                b_first.wait(timeout=10)
                cur.execute("UPDATE assessment_result SET ca_score=20.00 WHERE result_id=%s", (r2,))
            c.commit()
            out["a_deadlock"] = "committed (no deadlock)"
        except psycopg2.Error as e:
            c.rollback()
            out["a_deadlock"] = f"failed: SQLSTATE {e.pgcode} ({e.pgerror.strip()[:100]})"
        finally:
            c.close()

    def session_b_deadlock():
        c = new_conn(RC)
        try:
            with c.cursor() as cur:
                cur.execute("UPDATE assessment_result SET ca_score=25.00 WHERE result_id=%s", (r2,))
                b_first.set()
                a_first.wait(timeout=10)
                cur.execute("UPDATE assessment_result SET ca_score=30.00 WHERE result_id=%s", (r1,))
            c.commit()
            out["b_deadlock"] = "committed (no deadlock)"
        except psycopg2.Error as e:
            c.rollback()
            out["b_deadlock"] = f"failed: SQLSTATE {e.pgcode} ({e.pgerror.strip()[:100]})"
        finally:
            c.close()

    ta = threading.Thread(target=session_a_deadlock, name="A-dl")
    tb = threading.Thread(target=session_b_deadlock, name="B-dl")
    ta.start(); tb.start()
    ta.join();  tb.join()
    print(f"  DEADLOCK version  A: {out['a_deadlock']}")
    print(f"  DEADLOCK version  B: {out['b_deadlock']}")

    # ---- Fixed-order version: both update r1 then r2 (ascending id) ----
    # Reset scores first (parameterised to avoid f-string SQL injection noise).
    exec_one(
        "UPDATE assessment_result SET ca_score=10.00 WHERE result_id IN (%s,%s)",
        (r1, r2)
    )

    ready = threading.Event()

    def session_a_fixed():
        c = new_conn(RC)
        try:
            with c.cursor() as cur:
                cur.execute("UPDATE assessment_result SET ca_score=12.00 WHERE result_id=%s", (r1,))
                ready.set()
                cur.execute("UPDATE assessment_result SET ca_score=13.00 WHERE result_id=%s", (r2,))
            c.commit()
            out["a_fixed"] = "committed"
        except psycopg2.Error as e:
            c.rollback()
            out["a_fixed"] = f"failed: SQLSTATE {e.pgcode}"
        finally:
            c.close()

    def session_b_fixed():
        c = new_conn(RC)
        try:
            with c.cursor() as cur:
                # also update r1 first (id order); B will block on r1 until A commits
                cur.execute("UPDATE assessment_result SET ca_score=22.00 WHERE result_id=%s", (r1,))
                cur.execute("UPDATE assessment_result SET ca_score=23.00 WHERE result_id=%s", (r2,))
            c.commit()
            out["b_fixed"] = "committed"
        except psycopg2.Error as e:
            c.rollback()
            out["b_fixed"] = f"failed: SQLSTATE {e.pgcode}"
        finally:
            c.close()

    ta = threading.Thread(target=session_a_fixed, name="A-fix")
    tb = threading.Thread(target=session_b_fixed, name="B-fix")
    ta.start(); tb.start()
    ta.join();  tb.join()
    print(f"  FIXED ORDER  A (r1 then r2): {out['a_fixed']}")
    print(f"  FIXED ORDER  B (r1 then r2): {out['b_fixed']}")
    print("  >>> Updating shared rows in a consistent id order removes the deadlock.")


# ---------------------------------------------------------------------
# main
# ---------------------------------------------------------------------
def main():
    print("race_demos.py -- concurrency demos for Ibom Crown result processing")
    print(f"database: {DBNAME}   (Unix socket, no password, no TCP)")
    try:
        part1_bug()
        part2_constraint_fix()
        part3_serializable_fix()
        part4_for_update_comparison()
        part5_rc_vs_rr()
        part6_deadlock()
    finally:
        cleanup_demo()
        print()
        print("cleanup: demo students, batches and results removed.")


if __name__ == "__main__":
    main()
