-- snowflake/roles_and_grants.sql
-- Roles and grants, so a new Snowflake account can be rebuilt from the repo. Safe to re-run.
-- Order: job_pipeline_snowflake.sql -> part 1 of this file -> first `dbt build` -> part 2 of this
-- file -> curated_stage.sql.
--
--   JOB_PIPELINE_DEV       dbt and pipeline/run_pipeline.py: loads RAW, builds STAGING, INTERMEDIATE,
--                          MARTS and SEEDS, unloads MARTS to the curated stage
--   JOB_PIPELINE_REPORTER  Power BI: reads MARTS and nothing else (data_model.md, section 7.4)

use role securityadmin;

create role if not exists job_pipeline_dev      comment = 'dbt and the pipeline runner';
create role if not exists job_pipeline_reporter comment = 'Power BI: read-only on MARTS';
grant role job_pipeline_dev      to role sysadmin;
grant role job_pipeline_reporter to role sysadmin;


-- ---------- Part 1: JOB_PIPELINE_DEV (before the first dbt build) ----------
grant usage         on warehouse job_pipeline_wh to role job_pipeline_dev;
grant usage         on database  job_pipeline_db to role job_pipeline_dev;
grant create schema on database  job_pipeline_db to role job_pipeline_dev;   -- dbt creates and owns STAGING, INTERMEDIATE, MARTS, SEEDS

grant usage          on schema job_pipeline_db.raw to role job_pipeline_dev;
grant select, insert on all tables    in schema job_pipeline_db.raw to role job_pipeline_dev;   -- dbt sources + COPY INTO
grant select, insert on future tables in schema job_pipeline_db.raw to role job_pipeline_dev;
grant usage          on stage job_pipeline_db.raw.raw_stage to role job_pipeline_dev;           -- macros/load_raw.sql

-- every teammate who runs dbt:
-- grant role job_pipeline_dev to user <user_name>;


-- ---------- Part 2: JOB_PIPELINE_REPORTER (after the first dbt build, once MARTS exists) ----------
grant usage  on warehouse job_pipeline_wh     to role job_pipeline_reporter;
grant usage  on database  job_pipeline_db     to role job_pipeline_reporter;
grant usage  on schema    job_pipeline_db.marts to role job_pipeline_reporter;
grant select on all tables    in schema job_pipeline_db.marts to role job_pipeline_reporter;
grant select on future tables in schema job_pipeline_db.marts to role job_pipeline_reporter;  -- dbt re-creates the tables on every build

-- the user Power BI signs in with:
-- grant role job_pipeline_reporter to user <power_bi_user>;

-- check, as the reporter: MARTS is visible, STAGING and RAW are not
-- use role job_pipeline_reporter;
-- select count(*) from job_pipeline_db.marts.fct_jobs;          -- works
-- select count(*) from job_pipeline_db.staging.stg_ashby_jobs;  -- fails: does not exist or not authorized
