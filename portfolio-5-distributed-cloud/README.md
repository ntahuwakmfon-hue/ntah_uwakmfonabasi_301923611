# Portfolio 5 — Distributed / Cloud

**Database:** `resultsys` (PostgreSQL 16 + MongoDB 7+)

## What this portfolio does

Two deliverables:

1. `01_partitioning.sql` — demonstrates monthly RANGE partitioning of the biggest table (`assessment_result`) on a partitioned copy `assessment_result_part`. Uses a `DO` loop to create one partition per month covering every month present in the data plus next month, plus a `DEFAULT` partition. Prints the row count per partition and a pruned one-month `EXPLAIN ANALYZE`.
2. `cloud_design.md` — a managed-database design (multi-AZ, synchronous standby, asynchronous read replica, automated backups) with the synchronous vs asynchronous replication trade-off spelled out, and the Nigerian data-protection (NDPA 2023) and NUC record-keeping considerations that shape it.

## Files

| File | What it does |
| --- | --- |
| `01_partitioning.sql` | Creates `assessment_result_part` partitioned by RANGE on `created_at`. The primary key is `(result_id, created_at)` because every unique key on a partitioned parent must include the partition key. A `DO` loop creates monthly partitions for every month in the data plus next month, plus a `DEFAULT` partition. Migrates all rows from `assessment_result`, then prints rows-per-partition and a pruned `EXPLAIN (ANALYZE, BUFFERS)` for one month. |
| `cloud_design.md` | Managed PostgreSQL 16 on AWS RDS / Azure Database, multi-AZ synchronous standby (zero-loss), asynchronous read replica for reporting, automated PITR + nightly logical + cross-region copy backups. Spells out the sync-vs-async trade-off, why academic records must never be lost, NDPA 2023 §§34–38 (data subject rights), §40 (72-hour breach notification), §§41–43 (cross-border transfer / residency question), and NUC BMAS / CCMAS record-keeping expectations. |

## Partitioning design notes

- **Partition key:** `created_at` (TIMESTAMPTZ). Monthly granularity matches how the records office thinks about result batches.
- **Primary key:** `(result_id, created_at)`. PostgreSQL requires every unique key on a partitioned table to include the partition key. The original `assessment_result` table has `result_id` alone as PK; the partitioned copy therefore widens the PK to include `created_at`.
- **No exclusion constraints.** PG16 does not allow exclusion constraints on a partitioned parent, so none are used. The partial UNIQUE index `one_active_result_per_student_course_semester` from `01_schema.sql` cannot be recreated on the partitioned parent (PostgreSQL does not allow unique indexes without the partition key on partitioned tables). The copy in this file does **not** carry that constraint; it is purely a partitioning demonstration. In a production deployment the schema in `01_schema.sql` would be redesigned from day one as partitioned, with the partial unique constraint rebuilt as `(matric_no, course_id, semester_id, created_at) WHERE superseded = FALSE`.
- **DEFAULT partition:** catches any row whose `created_at` falls outside the explicitly created months. The `DO` loop creates monthly partitions through next month, so the DEFAULT partition should normally be empty — its presence is a safety net for mis-typed timestamps.

## How to run

```bash
psql -d resultsys -v ON_ERROR_STOP=1 -f 01_partitioning.sql
```

## Expected output

After the script runs, the `DO` block prints `partition ar_part_YYYY_MM: N rows` for every partition (and `ar_part_default: 0 rows` if no row falls outside the monthly range), followed by a pruned `EXPLAIN (ANALYZE, BUFFERS)` plan that scans only the one month's partition. Paste the real output below:

```
[paste real output here]
```

## Cloud design summary

See `cloud_design.md` for the full text. The headline decisions:

- Multi-AZ primary + **synchronous** standby (zero-loss failover for Senate-published records).
- Asynchronous read replica in a third AZ (low-latency reporting).
- Continuous WAL archive for PITR + nightly logical snapshot + cross-region copy.
- **Residency is an open question**: AWS `af-south-1` (Cape Town) and Azure `South Africa North` (Johannesburg) are in South Africa, not Nigeria. Storing student personal data there is a cross-border transfer under NDPA §§41–43 and must be resolved before go-live.
- NDPA §40: 72-hour breach notification to the NDPC; the monitoring stack pages on standby failover, replica lag, and audit-id gaps.
- NUC BMAS / CCMAS: academic records are retained permanently for graduated students and for the duration of the programme plus NYSC for non-graduated; `PUBLISHED` rows are append-only (supersede, never delete).
