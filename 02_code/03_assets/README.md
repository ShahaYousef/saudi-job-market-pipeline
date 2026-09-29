<!-- 02_code/03_assets/README.md -->
# 03_assets

Images that document the project: the data model, the dbt lineage, the dashboard pages, and
screenshots of the data-quality checks run in Snowflake on the final build (run `20260929T115551Z`, data collected up
to 28 September 2026). The code that produces the data is in `02_src/`; this folder holds the
evidence, so a reviewer can see the results without running the pipeline.

## Contents

| Path | What it shows |
|---|---|
| `schema_diagram.png` | The star schema in the Snowflake `MARTS` schema: `fct_jobs`, eight dimensions and `bridge_job_skill`, with keys and relationships |
| `dbt_lineage.png` | The dbt lineage graph: RAW sources → staging views → intermediate tables → marts, with the seeds that feed them |
| `test_results/` | Screenshots of the data-quality checks, one per layer, described below |
| `dashboard_01_cover.png` to `dashboard_08_coverage.png` | The eight pages of the Power BI dashboard (`02_src/powerbi/`), on the final build |

## test_results/

The screenshots follow the data through the layers. Each one is a SQL check run in a Snowflake
worksheet; the same rules are enforced automatically by the dbt tests in `02_src/dbt/tests/` and
`02_src/dbt/models/*/schema.yml` on every `dbt build` (288 data tests, 323 checks passed, 0
warnings, 0 errors on the final build).

### RAW → STAGING

| Screenshot | What it checks | Result |
|---|---|---|
| `RAW vs STAGING.png` | Job records in RAW per source against the records kept in staging; the gap is non-Saudi postings removed by the scope filter | Ashby 227 → 222 and Greenhouse 867 → 843 (29 non-Saudi postings removed); every other source keeps all its records |
| `Staging Model Integrity.png` | Per source: listings, null source IDs, invalid copy counts, invalid dates, duplicate groups | 20,490 listings across six sources; 0 on every check |
| `Duplicates.png` | The same posting (source + source job ID) appears only once per source after staging deduplication | 0 duplicate groups in all six sources |

### STAGING → INTERMEDIATE

| Screenshot | What it checks | Result |
|---|---|---|
| `Record Reconciliation.png` | Rows per source in staging against rows in `int_job_listings` | Identical for all six sources (difference 0): no listing is lost or added |
| `Data Quality.png` | Required fields on the 20,490 listings | No null source ID, empty title or empty company name; 3 listings without a location and 7 without a description are kept and shown as Unknown; 1,750 aggregator listings carry no job URL |
| `Intermediate Transformation 1.png` | Matching keys built for cross-source matching | Every listing has a normalized title; 2,599 have no company key (undisclosed employer, never matched); 424 are at country level with no standard city or region |
| `Intermediate Transformation 2.png` | Standardised values | Every listing has a standard country; no future posting dates; no first-seen date after the last-seen date; no invalid copy counts; 66 salaries paid by the hour or day keep no monthly SAR value by design |
| `Data Transformation.png` | Dates, salary and copy counts after transformation | 13,719 listings without a posting date (the source does not publish one); 0 future dates; 0 invalid date orders; 0 invalid copy counts |

### MARTS

| Screenshot | What it checks | Result |
|---|---|---|
| `Final Data Quality.png` | Keys and measures of `fct_jobs`, the final fact table | 19,148 jobs; no null key (missing values point to the Unknown member `-1` of each dimension); every job has a source; `job_count` = 1 on every row |

The rules behind the checks (which failures stop a run and which only warn) are in
`02_src/dbt/DATA_QUALITY.md`; the data model and every design decision are in
`02_src/dbt/data_modeling/data_model.md`.
