<!-- 02_code/01_data/final_datasets/README.md -->
# Final datasets — Job Market Data Pipeline (Saudi Arabia)

Exports of the ten tables in Snowflake schema `JOB_PIPELINE_DB.MARTS`: the star schema that
Power BI reads. One CSV per table, UTF-8, with a header row. The same tables are in ADLS as
Parquet, `stjobdata26/curated/<table>/export_date=<date>/`.

| | |
|---|---|
| **Generated** | 2026-09-29, from the final build of 2026-09-29, data up to 2026-09-28 (323 checks passed, 0 warnings, 0 errors) |
| **Observation window** | September 2026: employer boards collected several times between 9 and 28 September; aggregators collected as a query campaign on 9–12 September and repeated on 27–28 September |
| **Sources** | Ashby, Greenhouse, SmartRecruiters, Workable (employer job boards); Jooble, JSearch (aggregators) |
| **Model** | `02_code/02_src/dbt/data_modeling/data_model.md`; diagram `02_code/03_assets/schema_diagram.png` |

## Files

| File | Rows | Grain |
|---|---:|---|
| `fct_jobs.csv` | 19,148 | One job: one job advertisement in one Saudi location, after merging its listings across sources |
| `dim_job_posting.csv` | 18,694 | One job posting (+ Unknown). A Workable posting open in several cities is one posting and one job per city |
| `dim_company.csv` | 3,005 | One employer after entity resolution (+ the Unknown member, `Employer not disclosed`) |
| `dim_location.csv` | 58 | One location at city, region or country level (+ Unknown) |
| `dim_role.csv` | 20 | One job category with its role family (+ Unknown) |
| `dim_job_attributes.csv` | 83 | One observed combination of employment type, workplace type, remote status, experience level and its basis (+ Unknown) |
| `dim_date.csv` | 3,003 | One day, from the oldest posting date to the latest collection (+ Unknown `-1`) |
| `dim_source.csv` | 6 | One source |
| `dim_skill.csv` | 126 | One canonical skill (+ Unknown) |
| `bridge_job_skill.csv` | 22,822 | One job per skill mentioned in its titles or descriptions |

Totals: 20,490 listings → 19,148 jobs → 18,693 job postings. 1,008 jobs (5.3%) were found on more than
one source. Lifecycle: 2,584 open and 177 disappeared (employer-board evidence); 16,387 jobs found
on aggregators only are `unknown`. 174 jobs are new openings (employer-board jobs not seen in any
baseline pull).

## Columns

### `fct_jobs`

| Column | Meaning |
|---|---|
| `job_sk` | Key of the job |
| `posting_sk` | → `dim_job_posting`. Count postings as `COUNT(DISTINCT posting_sk)` |
| `company_sk` | → `dim_company` (`-1` = employer not disclosed: no name, or a placeholder such as `Confidential`) |
| `location_sk` | → `dim_location` |
| `role_sk` | → `dim_role` (`-1` = no usable title) |
| `job_attributes_sk` | → `dim_job_attributes` (`-1` = all attributes unknown) |
| `primary_source_sk` | → `dim_source`: source of the listing that represents the job |
| `posting_date_sk` | → `dim_date`: earliest employer-board posting date, else the earliest of any listing |
| `first_seen_date_sk`, `last_seen_date_sk` | → `dim_date`: first and last collection that returned the job |
| `opening_date_sk` | → `dim_date`: set only for a new opening (an employer-board job no baseline pull saw) |
| `open_until_date_sk` | → `dim_date`: last day the job counts as open |
| `disappeared_date_sk` | → `dim_date`: set only when `lifecycle_status = 'disappeared'` |
| `lifecycle_status` | `open` (still on an employer board), `disappeared` (gone from every board that listed it), `unknown` (found on aggregators only) |
| `status_basis` | `employer board` (the job has an ATS listing) or `aggregator query` (aggregators only) |
| `is_baseline` | Seen in the first pull of its board or source, so it existed before collection started |
| `is_censored` | The job has not disappeared, so its duration is not complete |
| `match_tier` | `single`, `exact` or `fuzzy`: how the job's listings were merged |
| `job_count` | 1 per row. Jobs = `SUM(job_count)` |
| `listing_count` | Listings merged into the job |
| `listing_count_workable` … `listing_count_jooble` | The same per source; the six add up to `listing_count` |
| `copies_landed` | Copies of those listings landed in RAW before deduplication |
| `source_count` | Distinct sources among the listings (1–6). Non-additive |
| `days_listed` | Disappeared jobs only: days from the posting date (else first seen) to the disappeared date. Summarize with a median |
| `days_listed_basis` | `posted` or `first_seen` |
| `salary_text` | Salary as published, from the listing the parsed salary fields come from |
| `salary_currency`, `salary_period` | `SAR` / `USD`; `hour`, `day`, `week`, `month`, `year` |
| `salary_min_amount`, `salary_max_amount` | As published |
| `salary_min_sar_month`, `salary_max_sar_month` | Converted to SAR per month for month, week and year; empty for hour and day |

### Dimensions and bridge

| Table | Columns |
|---|---|
| `dim_job_posting` | `posting_sk`, `job_title`, `description_text`, `description_basis` (`full` / `snippet` / `none`), `job_url`, `apply_url`: what the posting itself says |
| `dim_company` | `company_sk`, `company_name`, `company_norm`, `industry`, `is_recruitment_agency` (`true` for recruitment agencies and job boards, which advertise for other employers) |
| `dim_location` | `location_sk`, `city`, `region`, `country`, `location_level` (`city` / `region` / `country`), `location_label` (display name, e.g. `Riyadh (no city given)` for a region-level row) |
| `dim_role` | `role_sk`, `job_category`, `role_family` |
| `dim_job_attributes` | `job_attributes_sk`, `employment_type`, `workplace_type`, `remote_status`, `experience_level`, `experience_level_basis` (`source` / `title` / `unknown`) |
| `dim_date` | `date_sk`, `full_date`, `day_of_week`, `week_start_date` (Sunday), `month`, `quarter`, `year`, `is_weekend` (Fri–Sat) |
| `dim_source` | `source_sk`, `source_name`, `source_type` (`ATS` / `Aggregator`), `collection_method`, `source_priority` |
| `dim_skill` | `skill_sk`, `skill_name`, `skill_group` |
| `bridge_job_skill` | `job_sk`, `skill_sk`, `matched_in` (`title` / `description`). Count jobs as `COUNT(DISTINCT job_sk)` when a skill is in the filter |

## How the files were produced

For each table, in a Snowflake worksheet: `select * from job_pipeline_db.marts.<table>;`, then
**Download results → CSV**. Row counts were checked against `show tables in schema
job_pipeline_db.marts` after the final build.

## Known limitations

See `dbt/data_modeling/data_model.md`, section 12. In short: cross-source overlap is a lower
bound (fuzzy matching merges only high-similarity titles; 18 of its 20 merges are the same job by title, 1 is a different job, 1 is uncertain);
experience level is sparse and partly read from titles; Jooble has no posting date and a snippet
description; aggregator-only jobs have `lifecycle_status = 'unknown'`; `disappeared` means the posting
left its employer board's public list, and its date is the first pull that confirmed it.