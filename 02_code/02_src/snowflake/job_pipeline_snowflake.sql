-- ============================================================
-- Warehouse, database, and RAW schema setup
-- Safe to re-run — IF NOT EXISTS makes every statement idempotent.
-- ============================================================

CREATE WAREHOUSE IF NOT EXISTS job_pipeline_wh
  WAREHOUSE_SIZE = 'XSMALL'
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE;

CREATE DATABASE IF NOT EXISTS job_pipeline_db;

CREATE SCHEMA IF NOT EXISTS job_pipeline_db.raw;

-- ============================================================
-- External stage — connects Snowflake to the ADLS "raw" container.
-- AZURE_SAS_TOKEN must be a User Delegation SAS (generated via
-- "Shared access tokens" at the container level, Signing method =
-- User delegation key, User-bound SAS = Enabled, Read+List only).
-- ============================================================

CREATE STAGE IF NOT EXISTS job_pipeline_db.raw.raw_stage
  URL = 'azure://stjobdata26.blob.core.windows.net/raw'
  CREDENTIALS = (AZURE_SAS_TOKEN = '<PASTE_CURRENT_TOKEN_HERE_NO_LEADING_QUESTION_MARK>')
  FILE_FORMAT = (TYPE = JSON);

-- To update the token later without recreating the stage:
-- ALTER STAGE job_pipeline_db.raw.raw_stage
--   SET CREDENTIALS = (AZURE_SAS_TOKEN = '<new_token>');

-- Quick verification:
-- LIST @job_pipeline_db.raw.raw_stage/ashby/;


-- ============================================================
-- RAW tables — one per source, identical shape (VARIANT + metadata).
-- COPY INTO is natively idempotent: Snowflake tracks already-loaded
-- files per table and skips them automatically on re-run.
-- ============================================================

-- ---------- ASHBY ----------
CREATE TABLE IF NOT EXISTS job_pipeline_db.raw.raw_ashby (
  raw_data   VARIANT,
  file_name  STRING,
  loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO job_pipeline_db.raw.raw_ashby (raw_data, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @job_pipeline_db.raw.raw_stage/ashby/
)
FILE_FORMAT = (TYPE = JSON)
PATTERN = '.*\.json';


-- ---------- WORKABLE ----------
CREATE TABLE IF NOT EXISTS job_pipeline_db.raw.raw_workable (
  raw_data   VARIANT,
  file_name  STRING,
  loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO job_pipeline_db.raw.raw_workable (raw_data, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @job_pipeline_db.raw.raw_stage/workable/
)
FILE_FORMAT = (TYPE = JSON)
PATTERN = '.*\.json';


-- ---------- JSEARCH ----------
CREATE TABLE IF NOT EXISTS job_pipeline_db.raw.raw_jsearch (
  raw_data   VARIANT,
  file_name  STRING,
  loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO job_pipeline_db.raw.raw_jsearch (raw_data, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @job_pipeline_db.raw.raw_stage/jsearch/
)
FILE_FORMAT = (TYPE = JSON)
PATTERN = '.*\.json';


-- ---------- JOOBLE ----------
CREATE TABLE IF NOT EXISTS job_pipeline_db.raw.raw_jooble (
  raw_data   VARIANT,
  file_name  STRING,
  loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO job_pipeline_db.raw.raw_jooble (raw_data, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @job_pipeline_db.raw.raw_stage/jooble/
)
FILE_FORMAT = (TYPE = JSON)
PATTERN = '.*\.json';


-- ---------- SMARTRECRUITERS ----------
-- Note: the ADLS folder name is case-sensitive ("smartrecruiters",
-- lowercase) — confirmed the hard way after a 0-files-processed error.
CREATE TABLE IF NOT EXISTS job_pipeline_db.raw.raw_smartrecruiters (
  raw_data   VARIANT,
  file_name  STRING,
  loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO job_pipeline_db.raw.raw_smartrecruiters (raw_data, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @job_pipeline_db.raw.raw_stage/smartrecruiters/
)
FILE_FORMAT = (TYPE = JSON)
PATTERN = '.*\.json';


-- ---------- GREENHOUSE ----------
CREATE TABLE IF NOT EXISTS job_pipeline_db.raw.raw_greenhouse (
  raw_data   VARIANT,
  file_name  STRING,
  loaded_at  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

COPY INTO job_pipeline_db.raw.raw_greenhouse (raw_data, file_name)
FROM (
  SELECT $1, METADATA$FILENAME
  FROM @job_pipeline_db.raw.raw_stage/greenhouse/
)
FILE_FORMAT = (TYPE = JSON)
PATTERN = '.*\.json';