-- snowflake/curated_stage.sql
--
-- External stage for the curated export: MARTS -> ADLS container "curated" (Parquet).
-- Used by the dbt macro export_marts (dbt/macros/export_marts.sql) and the "export" step of
-- pipeline/run_pipeline.py.
--
-- Before running:
--   1. Azure Portal -> storage account stjobdata26 -> Containers -> + Container -> name: curated
--   2. Container "curated" -> Shared access tokens -> permissions Read, Add, Create, Write, List
--      (no Delete), HTTPS only, expiry after the presentation. Signing key: key1 or key2 AFTER
--      the rotation. Scope: this container only, so this token cannot touch raw/.
--   3. Paste the token below in the worksheet only. Never save this file with a real token.

use role accountadmin;

create stage if not exists job_pipeline_db.marts.curated_stage
    url = 'azure://stjobdata26.blob.core.windows.net/curated/'
    credentials = (azure_sas_token = '<curated-container-sas-token>')
    comment = 'Unload target for the MARTS export (dbt macro export_marts)';

-- the dbt role runs the export
grant usage on stage job_pipeline_db.marts.curated_stage to role job_pipeline_dev;

-- check: after the first export, one Parquet file per table and export date
list @job_pipeline_db.marts.curated_stage;