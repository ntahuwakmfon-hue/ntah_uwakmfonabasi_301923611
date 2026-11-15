-- P5 - streaming replica behaviour tests (Ibom Crown University Result Processing). Run as the postgres OS user over the Unix socket.
\set ON_ERROR_STOP off
\echo === Replica tests ===
\connect -reuse-previous=off resultsys - /var/run/postgresql 5433
SELECT 'REPLICA' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
\echo --- T1. Attempt an INSERT on the REPLICA (port 5433). Must be rejected ---
INSERT INTO faculty (faculty_code, name, dean_name, location) VALUES ('RW0001', 'P5 replica write test', 'n/a', 'Uyo');
\connect -reuse-previous=off resultsys - /var/run/postgresql 5432
SELECT 'PRIMARY' AS server, current_setting('port') AS port, pg_is_in_recovery() AS in_recovery;
\echo --- T2. Insert a marker row on the PRIMARY (5432), then read it on the REPLICA (5433) ---
INSERT INTO faculty (faculty_code, name, dean_name, location) VALUES ('RP0001', 'P5-REPLICA-PROOF', 'n/a', 'Uyo');
SELECT pg_sleep(1);
SELECT application_name, state, sync_state, sent_lsn, replay_lsn, (sent_lsn - replay_lsn) AS bytes_behind FROM pg_stat_replication;
\connect -reuse-previous=off resultsys - /var/run/postgresql 5433
SELECT name, faculty_code FROM faculty WHERE faculty_code = 'RP0001';
\connect -reuse-previous=off resultsys - /var/run/postgresql 5432
DELETE FROM faculty WHERE faculty_code = 'RP0001';
SELECT pg_sleep(1);
\connect -reuse-previous=off resultsys - /var/run/postgresql 5433
SELECT count(*) AS marker_rows_left_on_replica FROM faculty WHERE faculty_code = 'RP0001';
