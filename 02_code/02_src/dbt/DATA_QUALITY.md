<!-- dbt/DATA_QUALITY.md -->
# Data quality policy

What stops the pipeline, what only warns, and where each check lives. `pipeline/run_pipeline.py`
runs the steps in order and stops at the first failure, so ADLS `curated/` and `final_datasets/`
only ever receive a build that passed every blocking check.

**Rule for every check:** if its failure would publish a wrong number, it blocks. If its failure only
lowers completeness, it warns.

| Level | Check | Where | Effect |
|---|---|---|---|
| Block | Every board of a source failed to download | `pipeline/ingestion/*/` (exit code 1) | Run stops at `extract` |
| Block | A file failed to upload to ADLS | `pipeline/landing/upload_to_adls.py` | Run stops at `upload` |
| Block | A landed file is not valid JSON | `macros/load_raw.sql` (`COPY INTO`, `ON_ERROR = ABORT_STATEMENT`) | Run stops at `load` |
| Block | An employer-board source is older than 15 days | `models/sources.yml` (`error_after`) | Run stops at `freshness` |
| Block | An employer board's latest successful pull holds less than half the postings of its pull before (boards with 10 or more postings) | `tests/assert_ats_latest_pull_not_collapsed.sql` | `dbt build` fails, no export |
| Block | Keys: `unique` and `not_null` on every model key (Workable: shortcode + city) | `models/*/schema.yml` | `dbt build` fails |
| Block | Closed vocabularies: employment type, workplace type, remote status, experience level and its basis, location level, source type, status basis, lifecycle status, match tier, salary currency and period, description basis | `models/*/schema.yml`, `seeds/schema.yml` | `dbt build` fails |
| Block | Referential integrity: `relationships` on every key of `fct_jobs` (six dimensions and six date roles) and of `bridge_job_skill`; exactly one Unknown member per dimension (dim_source has none: every job has a known source) | `models/marts/schema.yml`, `tests/generic/has_one_unknown_member.sql` | `dbt build` fails |
| Block | Reconciliation: RAW → staging → listings → matched → fact; per-source counts add up; copies ≥ listings | `tests/assert_raw_reconciles_with_staging.sql`, `assert_int_listings_keeps_every_staging_row.sql`, `assert_matching_keeps_every_listing.sql`, `assert_fct_jobs_reconciles_with_listings.sql` | `dbt build` fails |
| Block | Matching rules: one representative per opening; never two postings of one publisher on one source in one opening; one employer and one location per job; `job_sk` is the earliest listing; a fuzzy job joins exactly two groups | `tests/assert_one_representative_per_job.sql`, `tests/assert_publisher_rule.sql`, `tests/assert_job_survivorship.sql` | `dbt build` fails |
| Block | Grain and lifecycle: `posting_sk` + `location_sk` unique in `fct_jobs`; `lifecycle_status` is `unknown` exactly when `status_basis = 'aggregator query'`; a disappeared date exactly for disappeared jobs, after the job's last sighting on an employer board; no opening date for baseline or aggregator-only jobs; no job open after the latest successful pull | `models/marts/schema.yml`, `tests/assert_job_lifecycle_consistent.sql` | `dbt build` fails |
| Warn | An aggregator source is older than 8 days; an employer board is 8 to 15 days old | `models/sources.yml` (`warn_after`) | Printed; run continues |
| Warn | Empty title; title that normalizes to empty; HTML left in a description | `severity: warn` in `models/*/schema.yml` | Printed; run continues |
| Report | Landed files, failed pages, out-of-scope rows, duplicates removed; jobs by match tier and lifecycle status; new openings; sources fully pulled per week; skill coverage | `analyses/pipeline_audit.sql`, `analyses/intermediate_checks.sql`, `analyses/model_checks.sql` | Numbers for `data_model.md` section 10 and the slides |

An unmapped value (a new employment type or experience level from a source) fails `accepted_values`
on purpose. Map it in the seed or macro; do not widen the test.
