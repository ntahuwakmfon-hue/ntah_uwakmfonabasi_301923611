# References

Only sources actually consulted while building this portfolio are listed.
Every URL below was reachable at the time of writing. Where a section
number or page is cited, it is taken from the linked source.

---

## PostgreSQL 16

- PostgreSQL Global Development Group. *PostgreSQL 16 Documentation.*
  <https://www.postgresql.org/docs/16/>
  - `CREATE TABLE` (including partitioned tables and constraints):
    <https://www.postgresql.org/docs/16/ddl.html>
    and <https://www.postgresql.org/docs/16/sql-createtable.html>
  - Declarative partitioning (RANGE, monthly partitions, DEFAULT
    partition, unique-key must include partition key):
    <https://www.postgresql.org/docs/16/ddl-partitioning.html>
  - Transaction isolation (the canonical write-skew example used in
    Portfolio 3, REPEATABLE READ vs SERIALIZABLE, SQLSTATE 40001):
    <https://www.postgresql.org/docs/16/transaction-iso.html>
  - `EXPLAIN` (ANALYZE, BUFFERS), Seq Scan vs Index Scan vs Index-Only
    Scan:
    <https://www.postgresql.org/docs/16/sql-explain.html>
    and <https://www.postgresql.org/docs/16/performance-tips.html>
  - Trigger functions (BEFORE INSERT/UPDATE, transition tables):
    <https://www.postgresql.org/docs/16/trigger-definition.html>
  - Partial unique indexes (`WHERE superseded = FALSE`):
    <https://www.postgresql.org/docs/16/indexes-partial.html>
  - `generate_series` for bulk data loading:
    <https://www.postgresql.org/docs/16/functions-srf.html>

- Obe, R. & Hsu, L. (2017). *PostgreSQL: Up and Running* (3rd ed.).
  O'Reilly Media. — practical reference for indexing, partitioning and
  `EXPLAIN ANALYZE`.

- Winand, M. (2017). *SQL Performance Explained*. Markus Winand.
  <https://use-the-index-luke.com/> — the source for the "covering
  index with INCLUDE enables Index-Only Scan" reasoning used in
  Portfolio 2.

- Berenson, H., Bernstein, P., Gray, J., Melton, J., O'Neil, E. &
  O'Neil, P. (1995). *A Critique of ANSI SQL Isolation Levels.*
  SIGMOD 1995. — the paper that introduced the "write skew" anomaly
  used as the race scenario in Portfolio 3.

## MongoDB 7+

- MongoDB, Inc. *MongoDB 7.0 Documentation.*
  <https://www.mongodb.com/docs/v7.0/>
  - `$jsonSchema` object schema validation (including `oneOf`, `enum`,
    `additionalProperties`, `bsonType`):
    <https://www.mongodb.com/docs/v7.0/core/schema-validation/>
    and <https://www.mongodb.com/docs/v7.0/reference/operator/query/jsonSchema/>
  - `db.createCollection` with validator:
    <https://www.mongodb.com/docs/v7.0/reference/method/db.createCollection/>
  - `insertMany` (ordered vs unordered, batch size limits):
    <https://www.mongodb.com/docs/v7.0/reference/method/db.collection.insertMany/>
  - `cursor.explain("executionStats")`, `COLLSCAN` vs `IXSCAN`,
    `hint({$natural:1})`:
    <https://www.mongodb.com/docs/v7.0/reference/method/cursor.explain/>
    and <https://www.mongodb.com/docs/v7.0/explain-results/>
  - Aggregation pipeline (`$group`, `$project`, `$sort`, `$limit`):
    <https://www.mongodb.com/docs/v7.0/core/aggregation-pipeline/>

- Chodorow, K. (2019). *MongoDB: The Definitive Guide* (5th ed.).
  O'Reilly Media.

## psycopg2

- Psycopg Project. *psycopg2 documentation.*
  <https://www.psycopg.org/docs/>
  - `connection.set_session(isolation_level=...)`:
    <https://www.psycopg.org/docs/connection.html#connection.set_session>
  - Exception classes (`SerializationFailure`, `DeadlockDetected`,
    `sqlstate` codes `40001` / `40P01`):
    <https://www.psycopg.org/docs/module.html#exceptions>
    and <https://www.psycopg.org/docs/errors.html>

## Distributed systems and databases

- Kleppmann, M. (2017). *Designing Data-Intensive Applications.*
  O'Reilly Media. — chapters 5 (Replication, sync vs async), 6
  (Partitioning), 7 (Transactions, isolation levels and write skew).

- Silberschatz, A., Korth, H. F. & Sudarshan, S. (2020). *Database
  System Concepts* (7th ed.). McGraw-Hill. — chapters on transaction
  management, isolation levels, normalisation (3NF).

- Elmasri, R. & Navathe, S. B. (2017). *Fundamentals of Database
  Systems* (7th ed.). Pearson. — ER modelling, functional dependencies,
  3NF.

## Nigeria — data protection and NUC

- Federal Republic of Nigeria. *Nigeria Data Protection Act, 2023.*
  Available at the Nigeria Data Protection Commission:
  <https://www.ndpc.gov-ng/> and an unofficial but widely-cited copy at
  <https://dataprotection.africa/wp-content/uploads/Nigeria_DPA.pdf>
  - Section 5 (objectives of the Act).
  - Sections 34–38 (rights of data subjects: access, rectification,
    erasure, restriction of processing, objection, data portability,
    complaint to the NDPC).
  - Section 40 (72-hour breach notification to the NDPC).
  - Sections 41–43 (cross-border transfer of personal data; adequacy;
    other bases).
  - The Act establishes the Nigeria Data Protection Commission (NDPC).

  Verified via the ICLG Nigeria data-protection chapter
  (<https://iclg.com/practice-areas/data-protection-laws-and-regulations/nigeria>)
  and the Legal500 cross-border transfer guide
  (<https://www.legal500.com/intelligence/nigeria/privacy/cross-border-data-transfers-under-nigerias-ndpa-a-compliance-guide>).

- National Universities Commission (NUC), Nigeria.
  <https://www.nuc.edu-ng/>
  - *Benchmark Minimum Academic Standards (BMAS)* — published 2007
    onward for 12 broad discipline groupings; the BMAS specifies the
    5-point grading scale (A=5, B=4, C=3, D=2, E=1, F=0) used in this
    portfolio's `grading_scale` table.
  - *Core Curriculum Minimum Academic Standards (CCMAS)* — began
    replacing BMAS from 2022.
  - Accreditation expectations: universities must score 70% across
    academics, staffing, facilities and library for full NUC
    accreditation, with complete retrievable academic records expected
    to be produced on demand for accreditation visits.

- Educators Without Borders (open educational resource). *Nigerian
  University Transcript Format (NUC guidelines, course codes, credit
  units, grade letters, CGPA).*
  <https://openeducat.org/gradebook/nigeria/transcripts>

## Cloud — managed PostgreSQL regions

- Amazon Web Services. *AWS Regions: Africa (Cape Town) — `af-south-1`.*
  <https://aws.amazon.com/about-aws/global-infrastructure/regions_az/>
- Microsoft Azure. *Azure regions: South Africa North (Johannesburg),
  South Africa West (Cape Town).*
  <https://azure.microsoft.com/en-us/explore/regions/>
- (No Google Cloud region on the African continent as of late 2025; not
  cited as a candidate for this design.)

## Nigerian locations, names and Naira

- The case study's geography (Uyo, Eket, Abak in Akwa Ibom State;
  Calabar in Cross River State; the state-of-origin list in
  `04_bulk_data.sql`) follows the structure of the 36 Nigerian states
  and the Federal Capital Territory.
- Tuition figures in `student.tuition_ngn` (₦250,000 – ₦400,000) are
  illustrative Naira amounts for a private Nigerian university; they
  are not taken from any specific university's published fee schedule.
