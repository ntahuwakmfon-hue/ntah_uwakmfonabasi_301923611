# Cloud design — Ibom Crown University result processing

This note describes a managed-database deployment for the Ibom Crown
University result processing subsystem on a public cloud, the
synchronous vs asynchronous replication trade-off (with the explicit
decision to favour zero loss for academic records), and the Nigerian
data-protection and NUC record-keeping considerations that shape the
design.

It is a *design* document. The SQL in `01_partitioning.sql` is the
local single-node demonstration of the partitioning strategy used on the
primary.

---

## 1. Workload profile

| Property | Value |
| --- | --- |
| Peak write rate | Exam week: ~50 results/sec sustained, ~500/sec burst when a batch is uploaded |
| Steady write rate | Off-peak: ~1 result/sec |
| Read rate | Transcript reads dominate off-peak; result-sheet reads dominate exam week |
| Biggest table | `assessment_result` (~60k rows now; expect ~500k rows/year) |
| Retention | Permanent for graduated students; minimum 5 years for non-graduated |
| RTO (recovery time objective) | 1 hour during exam week; 4 hours off-peak |
| RPO (recovery point objective) | **0** for `PUBLISHED` batches; **≤ 5 minutes** for `PENDING` / `DRAFT` |

The RPO of 0 for published batches is non-negotiable: once Senate has
published a batch, that result is the student's official academic record
and may not be silently lost.

---

## 2. Managed database choice

**Recommended:** a managed PostgreSQL 16 service — AWS RDS for PostgreSQL
or Azure Database for PostgreSQL — Flexible Server. Both expose PG16,
automatic PITR (point-in-time recovery), read replicas, and multi-AZ
high availability without requiring the university to operate Postgres
internally.

PostgreSQL 16 is the version targeted by Portfolios 1–3 and 5, so a
managed service that ships exactly that major version is required. The
MongoDB audit and transcript store (Portfolio 4) is deployed separately
as a managed MongoDB Atlas M10+ cluster (or DocumentDB for AWS-only
shops) with the same durability profile.

### 2.1 Topology

```
                                   ┌─────────────────────────────┐
                                   │   Application tier          │
                                   │   (exam officer UI,         │
                                   │    student transcript API)  │
                                   └──────────────┬──────────────┘
                                                  │
                          ┌───────────────────────┴────────────────────────┐
                          │   Managed PostgreSQL 16 (primary, multi-AZ)    │
                          │   - PG16, timezone Africa/Lagos                │
                          │   - synchronous_commit = on                    │
                          │   - WAL streaming to standby (SYNC)            │
                          │   - automated PITR backups (every 5 min)       │
                          │   - nightly logical snapshot to object store   │
                          └──────────┬──────────────────────┬──────────────┘
                                     │ SYNC (zero-loss)     │ ASYNC (low latency)
                                     ▼                      ▼
                       ┌──────────────────────┐   ┌─────────────────────────┐
                       │  Synchronous standby │   │  Read replica (reporting)│
                       │  (failover target)   │   │  - transcript reads      │
                       │  different AZ        │   │  - aggregate reports     │
                       └──────────────────────┘   └─────────────────────────┘
```

### 2.2 Multi-AZ (synchronous standby)

The primary and a synchronous standby run in **two availability zones**
within the same cloud region. WAL streaming is configured with
`synchronous_standby_names = 'FIRST 1 (*)'` so every commit waits for
the standby to flush the WAL record to disk before acknowledging to the
client. Failover to the standby is automatic (typically 60–90 seconds)
and loses **zero** committed transactions.

### 2.3 Read replica (asynchronous)

A second replica in a third AZ runs **asynchronous** streaming
replication and serves read-only traffic: transcript reads (students
viewing their own transcripts), aggregate reports (pass rate per
department, grade distribution), and ad-hoc analytical queries from
Portfolio 2. Asynchronous replication keeps commit latency low — the
primary does not wait for the read replica.

Replication lag on the read replica is monitored; if it exceeds 30
seconds, the application tier is signalled to route reads back to the
primary until lag returns to normal. The read replica is never used for
writes or for serving a freshly published batch (the publish transaction
goes to the primary).

### 2.4 Backups

| Backup type | Frequency | Retention | Purpose |
| --- | --- | --- | --- |
| Automated WAL archive | continuous | 35 days | PITR to any second within the retention window |
| Automated snapshot | daily | 30 days | Quick restore to a known-good daily state |
| Logical snapshot (`pg_dump` of `resultsys`) | nightly | 12 months | Cross-region disaster recovery; NDPA "data portability" support |
| Cross-region copy of nightly snapshot | nightly | 12 months | Region-level disaster recovery |

The nightly logical snapshot is also the artefact used to satisfy the
"rectification" and "erasure" requests under NDPA — a snapshot is
preserved for 12 months so a corrected transcript can be re-issued from
a known state if a Senate-approved grade change must be reflected.

---

## 3. Synchronous vs asynchronous replication trade-off

### 3.1 The two modes

| Mode | Commit acknowledgement | Data loss on primary failure | Commit latency |
| --- | --- | --- | --- |
| Synchronous (SYNC) | Waits for standby to flush WAL | **Zero** | Higher (one round-trip to standby) |
| Asynchronous (ASYNC) | Returns on local WAL flush | May lose last few committed transactions | Lower |

### 3.2 Why SYNC for the primary/standby pair

Academic records are **never** allowed to be silently lost. A
`PUBLISHED` batch is, by definition, the student's official result. If a
`PUBLISHED` row were lost in a failover, the university would face:

- Students whose transcripts no longer reflect Senate decisions, with no
  audit trail explaining the discrepancy.
- NUC accreditation fallout — see §4.2 — because accreditation reviews
  expect complete, retrievable records.
- Legal exposure under the NDPA data-subject rights in §§34–38 (the
  right of access and rectification collapses if the record itself is
  gone).
- Re-running Senate approval for the lost batch, which is operationally
  infeasible once Senate has risen.

Synchronous replication costs ~1–2 ms per commit on a cross-AZ link in
the same region. At the projected peak of 500 commits/sec that is a
trivial price for zero loss. The trade-off is asymmetric: the cost is
small and bounded; the loss scenario is catastrophic and unbounded.

### 3.3 Why ASYNC for the read replica

The read replica carries no Senate-critical writes — it only serves
read-only reporting. Asynchronous replication is the correct choice
because:

- Reporting traffic tolerates a few seconds of staleness ("the pass
  rate per department" does not need to be sub-second fresh).
- The replica can be paused, rebuilt, or relocated without stalling
  writes on the primary.
- Commit latency on the primary is not inflated by a third hop.

If the read replica fails, the application simply routes reads to the
primary until a new replica is provisioned. No data is lost.

### 3.4 The rule, in one sentence

> Senate-published results are replicated synchronously (zero-loss);
> reporting reads are served from an asynchronous replica (low-latency).
> Lossy failover is acceptable for in-flight `DRAFT` and `PENDING` rows
> (RPO ≤ 5 minutes via WAL archive) and **unacceptable** for
> `APPROVED` and `PUBLISHED` rows.

---

## 4. Nigerian data-protection and NUC notes

### 4.1 NDPA 2023

The Nigeria Data Protection Act 2023 (NDPA) governs the processing of
personal data in Nigeria and establishes the Nigeria Data Protection
Commission (NDPC). Student records are personal data — name, matric
number, gender, state of origin, transcript lines — and several sections
apply directly to this design:

- **Section 5** sets out the objectives of the Act, including
  safeguarding the fundamental rights and freedoms of data subjects.
- **Sections 34–38** enumerate the rights of data subjects: access,
  rectification, erasure, restriction of processing, objection, data
  portability, and the right to lodge a complaint with the NDPC. The
  transcript API in this design is the operational expression of the
  *access* right; the grade-change audit trail (Portfolio 1 trigger 4)
  supports *rectification*.
- **Section 40** requires the data controller to notify the NDPC of a
  personal data breach within **72 hours** of becoming aware of it.
  The cloud provider's breach-notification SLA and our own monitoring
  must let the records officer meet this window; this is the reason the
  monitoring stack pages on standby failover, replica lag, and any
  unexpected `audit_id` gap.
- **Sections 41–43** govern cross-border transfer of personal data.
  Personal data may not be transferred outside Nigeria unless one of the
  bases in §§41–43 is met (e.g. adequacy of protection in the recipient
  country, the data subject's consent, or one of the other listed
  bases). See §4.3 below — this is the residency question.

### 4.2 NUC record-keeping expectations

The National Universities Commission (NUC) accredits programmes in
Nigerian universities. From 2007 the NUC used the Benchmark Minimum
Academic Standards (BMAS); from 2022 the BMAS is being superseded by
the Core Curriculum Minimum Academic Standards (CCMAS). For
accreditation reviews, the NUC expects the university to produce, on
demand:

- Complete result sheets for sampled courses across multiple sessions.
- Senate approval minutes that match the published batches.
- Transcripts for sampled students.

The NUC does not fix a single numerical retention period in the BMAS or
CCMAS documents, but the operational expectation, reflected in
accreditation visits, is that **academic records are retained
permanently for graduated students** (so transcripts can be re-issued
decades later) and **for the duration of the programme plus the NYSC
service window** for non-graduated students. The 12-month logical
snapshot retention in §2.4 is the *operational* backup layer; the
*retention* layer is the primary database itself, which must never be
truncated (the schema is append-only for `PUBLISHED` rows — supersede
rather than delete).

### 4.3 Data residency question

The cloud regions available on AWS and Azure in Africa are in **South
Africa**, not Nigeria:

- **AWS:** `af-south-1` (Cape Town).
- **Azure:** `South Africa North` (Johannesburg) and `South Africa West`
  (Cape Town).

(As of late 2025 neither AWS nor Azure offers a region physically inside
Nigeria, and Google Cloud does not yet offer a region on the African
continent.)

Hosting student personal data in a South-Africa region is a
cross-border transfer under NDPA §§41–43 and may only be done where one
of the bases in those sections is met — most plausibly a determination
of adequacy of protection by the NDPC, or the data subject's consent.
**This is a residency question the university must resolve before
go-live**, and the options are:

1. **Self-host in Nigeria** on a local data centre or a Nigerian-located
   cloud provider (no cross-border transfer; the design in this note
   still applies, just on a self-managed PG cluster).
2. **Use a South-Africa region** with a documented NDPA §§41–43 basis
   (adequacy determination or consent), recorded in the records
   officer's data-protection register.
3. **Pseudonymise** student personal data before it leaves Nigeria
   (host the `student` and `assessment_result` tables in Nigeria; host
   only the audit log and aggregates in the cloud region). This is the
   most defensible hybrid but requires the application tier to do the
   pseudonymisation.

The design in this note does **not** assume that personal data may sit
outside Nigeria without one of the above being explicitly chosen and
documented.

---

## 5. Operational summary

| Decision | Choice | Reason |
| --- | --- | --- |
| Database engine | PostgreSQL 16 (managed) | Matches Portfolios 1–3, 5 |
| HA topology | Multi-AZ primary + synchronous standby | Zero-loss failover for Senate-published records |
| Read replica | Async, third AZ | Low-latency reads without slowing the primary |
| Backup | Continuous WAL + daily snapshot + nightly logical + cross-region copy | PITR + DR + NDPA portability |
| Partitioning | Monthly RANGE on `assessment_result.created_at` | Prunes month-scoped reports; see `01_partitioning.sql` |
| Cross-border transfer | **Open question** — must be resolved under NDPA §§41–43 before go-live | Residency |
| Breach notification | 72-hour SLA to NDPC under NDPA §40 | Monitoring + runbook |
| Record retention | Permanent for graduated; 5+ years for non-graduated; append-only for `PUBLISHED` | NUC accreditation expectations |
