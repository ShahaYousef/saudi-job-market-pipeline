<!-- snowflake/power_bi_access.md -->
# Power BI access to Snowflake

Power BI reads the star schema in `JOB_PIPELINE_DB.MARTS` and nothing else. RAW, STAGING,
INTERMEDIATE and SEEDS hold raw payloads, work tables and lookup data. A report built on them would
bypass the tests and the survivorship rules, so the report's connection is not allowed to see them.
The roles are created by `snowflake/roles_and_grants.sql`.

## 1. Roles

| Role | Used by | Can do |
|---|---|---|
| `JOB_PIPELINE_DEV` | dbt and `pipeline/run_pipeline.py` | Read and load RAW; create and own STAGING, INTERMEDIATE, MARTS and SEEDS; unload MARTS to the `curated` stage |
| `JOB_PIPELINE_REPORTER` | Power BI | Use the warehouse; **read** the tables in MARTS. Nothing else: no RAW, no STAGING, no writes |

Both roles are granted to `SYSADMIN`, so an administrator can still manage their objects.

## 2. Grants for the reporter

```sql
-- snowflake/roles_and_grants.sql, part 2 (after the first dbt build, once MARTS exists)
grant usage  on warehouse job_pipeline_wh       to role job_pipeline_reporter;
grant usage  on database  job_pipeline_db       to role job_pipeline_reporter;
grant usage  on schema    job_pipeline_db.marts to role job_pipeline_reporter;
grant select on all tables    in schema job_pipeline_db.marts to role job_pipeline_reporter;
grant select on future tables in schema job_pipeline_db.marts to role job_pipeline_reporter;

grant role job_pipeline_reporter to user <power_bi_user>;
```

- **`future tables`** is needed because dbt drops and re-creates each mart table on every build. Without it,
  Power BI would lose access after the next `dbt build`.
- **Read-only.** The reporter gets `select` only, so a report cannot change the data.
- **No other schemas.** The reporter has no `usage` on RAW, STAGING, INTERMEDIATE or SEEDS, so their
  tables do not exist for it.

## 3. The secondary-roles trap, and how it was checked

The first check ran as the reporter and queried one mart table and one staging table. **Both
worked**: `fct_jobs` returned its rows, and `stg_ashby_jobs` returned 49 rows, although the
reporter has no grant on STAGING.

The cause was Snowflake's secondary roles. A session uses its primary role **plus** every other
role granted to the user (`default_secondary_roles = ('ALL')`). The test user also held
`JOB_PIPELINE_DEV`, so the session silently had the developer's privileges.

Run with the primary role alone, the check gave the expected result:

```sql
use role job_pipeline_reporter;
use secondary roles none;
select count(*) from job_pipeline_db.marts.fct_jobs;          -- works: 19,148
select count(*) from job_pipeline_db.staging.stg_ashby_jobs;  -- fails: does not exist or not authorized
```

So the grants were right, and the leak came from the user. For the user Power BI signs in with:

```sql
alter user <power_bi_user> set default_role = job_pipeline_reporter
                               default_secondary_roles = ();   -- the session gets only the reporter's rights
```

The Power BI user should hold `JOB_PIPELINE_REPORTER` only. It should not be a personal account
that also holds `JOB_PIPELINE_DEV` or `ACCOUNTADMIN`.

## 4. Connecting Power BI

| Setting | Value |
|---|---|
| Connector | Snowflake (Get Data → Database → Snowflake) |
| Server | `<account_identifier>.snowflakecomputing.com` |
| Warehouse | The warehouse granted to the reporter |
| Advanced → Role | `JOB_PIPELINE_REPORTER` |
| Navigator | `JOB_PIPELINE_DB` → `MARTS` → the ten tables (fact, eight dimensions, bridge) |
| Mode | **Import**: the star is small (19,148 fact rows in the final build, data up to 28 September), and a refresh after each pipeline run is enough |
| Credentials | Entered in Power BI's credential store, never written into the `.pbix` or the repo |

Relationships in the model follow the star (data_model.md, section 7.4): each dimension one-to-many
to `fct_jobs`, filtering from the dimension to the fact. `dim_date` is related in six roles
(`posting_date_sk`, `first_seen_date_sk`, `last_seen_date_sk`, `opening_date_sk`,
`open_until_date_sk`, `disappeared_date_sk`); one is active, the others are used through
`USERELATIONSHIP` in DAX. Skills: `dim_skill` one-to-many `bridge_job_skill` many-to-one `fct_jobs`,
with the bridge to fact relationship filtering in both directions. Measures:

```
Job openings        = SUM ( fct_jobs[job_count] )
Job postings        = DISTINCTCOUNT ( fct_jobs[posting_sk] )
Listings            = SUM ( fct_jobs[listing_count] )
Jobs with skill     = DISTINCTCOUNT ( bridge_job_skill[job_sk] )
New openings        = CALCULATE ( SUM ( fct_jobs[job_count] ), fct_jobs[opening_date_sk] <> -1 )
Median days listed  = MEDIAN ( fct_jobs[days_listed] )
```

`lifecycle_status` is `unknown` for aggregator-only jobs (`status_basis = 'aggregator query'`): a
query result is not a full list, so a missing listing proves nothing. Visuals about open,
disappeared or new jobs describe employer-board jobs, and say so.

## 5. Checks before the presentation

1. As the Power BI user, run the four lines in Section 3: MARTS works and STAGING fails.
2. `show grants to role job_pipeline_reporter;` lists only usage on the warehouse, database and
   MARTS, and select on MARTS tables.
3. After a `dbt build`, refresh the report: it still loads, because of the future grants.