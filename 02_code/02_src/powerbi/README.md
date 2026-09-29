# powerbi/: dashboard on the MARTS schema

| File | What it is |
|---|---|
| `Job_Market_Data_Pipeline_GroupA_Dashboard_v1.pbix` | The Power BI report: 8 pages on the ten MARTS tables, imported from Snowflake |
| `measures_and_validation.dax` | Every report measure, plus one query that checks each against the value computed from the final datasets |
| `theme.json` | Report theme: the colours and font of the presentation |

## Open and refresh

1. Open the `.pbix` in Power BI Desktop (Windows).
2. To refresh from Snowflake, sign in when prompted and use the read-only role
   `JOB_PIPELINE_REPORTER` (created by `../snowflake/roles_and_grants.sql`, part 2).
   Without Snowflake access the report still opens with the data imported at the last refresh.

## Model

- Star schema as in `../dbt/data_modeling/data_model.md`: `FCT_JOBS` to each dimension, many to one,
  single direction; `BRIDGE_JOB_SKILL` between `FCT_JOBS` and `DIM_SKILL`.
- `DIM_DATE` is role-playing: `FIRST_SEEN_DATE_SK` is the active relationship; `POSTING_DATE_SK`,
  `OPENING_DATE_SK` and `DISAPPEARED_DATE_SK` are inactive and used through `USERELATIONSHIP`.
- All numbers are measures in the `_Measures` table. Jobs are `SUM(FCT_JOBS[JOB_COUNT])`.

## Validation

Run `measures_and_validation.dax` in DAX query view. The first result has one row per check, and
every row must say `OK`: 43 checks, including 19,148 jobs, 20,490 listings, 2,584 open and 177
disappeared employer-board jobs, 174 new openings, and the answers to the business questions.

## Reading rules built into the pages

- Weekly counts by first-seen date reflect when sources were pulled, so market dynamics use only new
  openings and disappeared jobs on employer boards.
- Open or disappeared status exists only for employer-board jobs; aggregator results stay `unknown`.
- Shares of an attribute use only jobs where the source states it, and print that base.
- Experience levels use only levels stated by the source; skills use only jobs with a full description.
- Top employers exclude recruitment agencies and undisclosed employers.
