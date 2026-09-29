<!-- dbt/README.md -->
# dbt project — Job Market Data Pipeline

The transformation layer of the pipeline (ELT). Raw job postings land in Snowflake untouched;
everything in this folder turns them into a clean, tested, analysis-ready star schema.

```
RAW (Snowflake)  →  staging  →  intermediate            →  marts
6 VARIANT tables    6 views      int_landed_files          fct_jobs
                                 int_board_pulls           + 8 dimensions
                                 int_source_weeks          + bridge_job_skill
                                                           (tables)
                                 int_job_listings
                                 int_listing_groups
                                 int_match_candidates
                                 int_jobs_matched
                                 int_job_openings
                                 int_job_skills
                                 (tables)
```

| Layer | Schema | Materialized | What it does |
|---|---|---|---|
| staging | `STAGING` | view | One model per source: rename, cast, flatten, deduplicate within the source, Saudi scope |
| intermediate | `INTERMEDIATE` | table | Union of the six sources, standardization through seeds, cross-source matching, survivorship |
| marts | `MARTS` | table | Star schema read by Power BI and exported to ADLS `curated/` |
| seeds | `SEEDS` | table | Ten lookup tables: cities, job categories, role families, company aliases, experience levels, sources, seniority keywords, skills, currency rates, and match review verdicts. `seed_company_aliases` holds 742 aliases; `analyses/companies_not_in_seed.sql` lists candidate spellings still outside it |

The design (grain, keys, matching rules, tests) is in
[`data_modeling/data_model.md`](data_modeling/data_model.md); the quality policy (what stops a run,
what only warns) is in [`DATA_QUALITY.md`](DATA_QUALITY.md).

## How to run

The whole pipeline, from `02_code/02_src`: `py pipeline/run_pipeline.py` (see `02_code/README.md`).
dbt on its own, from this folder:

```powershell
py -m dbt.cli.main deps                  # installs dbt_utils
py -m dbt.cli.main build                 # loads the seeds, runs every model and every test, in dependency order
```

Useful selections:

```powershell
py -m dbt.cli.main build --select staging
py -m dbt.cli.main build --select int_job_listings+     # a model and everything downstream of it
py -m dbt.cli.main run-operation load_raw               # COPY INTO RAW, new files only
py -m dbt.cli.main run-operation export_marts           # MARTS -> ADLS curated/ as Parquet
py -m dbt.cli.main docs generate
py -m dbt.cli.main docs serve                           # lineage graph
```

`py -m dbt.cli.main` is used instead of `dbt` because some managed Windows machines block `dbt.exe`.

---

## Staging layer

### Goal

Take each raw source exactly as it landed and produce a clean table with standardized column
names, converted types, and **no within-source duplicates**, without dropping any column that
might be useful later. The shared columns are identical across all six models so they can be
combined in intermediate. Source-specific columns stay in staging.

Staging does not join sources and applies no cross-source business rules. It applies the
geographic scope (Saudi Arabia) where extraction could let a non-Saudi posting through (Ashby,
Greenhouse), and flags whether an ATS posting is still on its board (`is_active`), because staging
is the last layer that sees every landed copy.

### Shared columns (all six models)

| Column | Type | Description |
|---|---|---|
| `source_record_sk` | STRING | Surrogate key, unique across all sources combined |
| `source_job_id` | STRING | The job's stable identifier within its source |
| `source_name` | STRING | `'ashby'`, `'workable'`, `'greenhouse'`, `'smartrecruiters'`, `'jooble'`, `'jsearch'` |
| `company_raw` | STRING | Company name as given by the source |
| `title_raw` | STRING | Job title |
| `location_raw` | STRING | Location as one line of text |
| `country_raw` / `city_raw` / `region_raw` | STRING | Structured location, where the source provides it |
| `workplace_type_raw` | STRING | `Remote` / `Hybrid` / `OnSite` / null, one vocabulary across sources |
| `employment_type` | STRING | Normalized by `normalize_employment_type()` |
| `description_plain` | STRING | Job description. **Plain text for Ashby / JSearch / Jooble; HTML for Workable / Greenhouse / SmartRecruiters**, stripped in intermediate |
| `job_url` / `apply_url` | STRING | Posting page and application page |
| `posting_date_raw` | TIMESTAMP_TZ (UTC) | Publish date; null where the source has no trustworthy one |
| `ingested_at` | TIMESTAMP_TZ (UTC) | When the record was collected, see below |
| `first_seen_at` / `last_seen_at` | TIMESTAMP_TZ (UTC) | Observation window across every landed copy |
| `copies_landed` | INT | Copies of the listing landed in RAW before deduplication |

ATS models (Ashby, Workable, Greenhouse, SmartRecruiters) also carry `ingest_date`,
`is_active`, `loaded_at`, and `file_name`. Jooble and JSearch carry `batch_id` and `http_status`.

### What `ingested_at` means per source

| Sources | `ingested_at` | Why |
|---|---|---|
| Jooble, JSearch | Collection timestamp recorded in each page's envelope | Exact per page. `loaded_at` is shared by a whole `COPY INTO` batch and cannot order copies |
| Ashby, Workable, Greenhouse, SmartRecruiters | `ingest_date` from the landing path, at midnight UTC | ATS files carry no collection timestamp. `loaded_at` records load time, not collection time |

`ingest_date` is read from the ADLS path by the `ingest_date_from_path()` macro:
`ashby/ingest_date=2026-09-16/alan.json` → `2026-09-16`.

### Surrogate key

`dbt_utils.generate_surrogate_key()` over `source_name` + `source_job_id` (plus `city_raw` for
Workable, see below). Job IDs are only unique within their own source, so the source name
prevents collisions once the models are combined.

### Employment type normalization

`normalize_employment_type()` reconciles each source's spelling (`FullTime` / `Full-time`,
`Intern` / `Internship`, `Contract` / `Contractor`…) into one vocabulary. A posting open to both
full-time and part-time (`Full-time and Part-time`, `FULLTIME, PARTTIME`) keeps that value; any
other combination becomes `Other`. An unrecognized value passes through unchanged rather than
becoming null, so the `accepted_values` test fails and a new spelling gets noticed instead of
silently disappearing.

### Two kinds of duplication

1. **Within-source duplication, handled in staging.** The same posting, under the same source
   ID, landed more than once.
   - **Jooble / JSearch:** overlapping queries return the same posting many times.
   - **ATS sources:** the same posting appears in every `ingest_date` snapshot while it stays open.

   Every model keeps the most recent copy
   (`qualify row_number() over (partition by <key> order by <collection time> desc …) = 1`) and
   computes `first_seen_at` / `last_seen_at` *before* dropping the older copies.

2. **Cross-source duplication, handled in intermediate.** The same real job published on
   different sources under different IDs. IDs cannot resolve this; it needs normalized matching
   on title, company and city. Specified in
   [`data_modeling/data_model.md`](data_modeling/data_model.md#8-cross-source-matching-specification).

### `is_active` (staging, employer boards only)

An ATS file is a full snapshot of a company's open jobs. A posting present in the latest pull of
its own board has `is_active` = true; one missing from it is false. This is the evidence for the
job lifecycle: `int_job_listings` marks a listing disappeared once `disappearance_misses`
successful pulls of its board confirm it, and `int_job_openings` sets `lifecycle_status` (`open`,
`disappeared`, `unknown`) in `fct_jobs`. A test (`assert_ats_latest_pull_not_collapsed`) stops
the build if a board's latest successful pull holds less than half the postings of its pull before
(boards with 10 or more postings; vars `ats_collapse_ratio`, `ats_collapse_min_postings`), so a
broken pull is never read as "everything closed".

Aggregator listings (Jooble, JSearch) have `is_active` = null: a search result is not a full list
of open jobs, so a listing missing from a later run proves nothing. Their jobs get
`lifecycle_status = 'unknown'` (`data_model.md`, section 7.1;
[`data_modeling/aggregator_status.md`](data_modeling/aggregator_status.md)).

### Per-model notes

**`stg_ashby_jobs`** — one file per company with a `jobs` array.
- Scope filter on `address.postalAddress.addressCountry = 'Saudi Arabia'`, with a keyword fallback
  when the field is missing. The extraction keyword filter matched `"hail"` inside
  `"Thailand (Remote)"`; this filter removes such postings.
- Ashby's API returns no company name, so `company_raw` is the board slug from the file name.
- `department` / `team` are unreliable: some companies put their own name there.
- `secondary_locations_raw` kept for reference.

**`stg_workable_jobs`** — one file per company with a `jobs` array.
- Grain is **one row per posting per city**. A role open in several cities arrives as one object
  per city under the same `shortcode`, so `city_raw` is part of the key and nothing is dropped.
- `company_raw` from the payload's own `name` field (e.g. `"Qiddiya Investment Company"`); the
  file-name slug is kept as `board_slug`.
- `apply_url` from `application_url`, the real application page.
- `region_raw` reads Workable's `state` field, which holds the region (e.g. `"Makkah Province"`).
- `workplace_type_raw` is `'Remote'` when `telecommuting = true`, otherwise null: Workable cannot
  distinguish Hybrid from OnSite.
- `posting_date_raw`: `published_on` (date only), falling back to `created_at`, at midnight UTC.
- Added `department`, `job_function`, `industry`, `education`.

**`stg_greenhouse_jobs`** — one file per board with a `jobs` array (17 boards).
- Deduplicated across snapshots **and across boards**: an umbrella board (`cssmerge`) can list the
  same posting as a brand's own board (`pronto`, `kitchenpark`, `namaa`) under the same ID.
- Scope filter on location keywords: the files of 2026-09-09 were not filtered at extraction
  (24 non-Saudi postings removed).
- Metadata (`Employment Type`, `Brand`) is extracted per file + job and aggregated to one row, so
  the join cannot fan out when more snapshots are loaded.
- `company_raw` has the `"Careers page"` suffix removed (`"ATOMS Careers page"` → `"ATOMS"`).
  `brand_raw` is kept separately; intermediate prefers the brand.
- Timestamps converted to UTC: Greenhouse returns local offsets (`-04:00`), not UTC.
- `posting_date_raw` uses `first_published`; `updated_at` mostly reflects the last sync time.
- No structured city / country and no remote signal in the payload.

**`stg_smartrecruiters_jobs`** — the file is a JSON array directly (no wrapper key).
- `job_url` / `apply_url` built as `https://jobs.smartrecruiters.com/<company.identifier>/<id>`.
  The raw `ref` field is an API endpoint, not a page a person can open; it is kept as `api_ref_url`.
- `location_raw` cleaned of empty parts (`"Riyadh, , Saudi Arabia"` → `"Riyadh, Saudi Arabia"`);
  `country_raw` upper-cased (`sa` → `SA`).
- The only source with separate `remote` and `hybrid` flags, so all three workplace types are distinguishable.
- Descriptive sections (`companyDescription`, `qualifications`, `additionalInformation`) kept as separate columns.

**`stg_jsearch_jobs`** — envelope per query page; jobs inside `response_raw` (escaped JSON string), array key `data`.
- `source_job_id` is `job_uid`, not `job_id`. `job_id` is base64 of `job_uid` plus a token that
  changes on every request (42 `job_uid`s map to more than one `job_id`); kept for traceability only.
- Only HTTP 200 pages parsed; `try_parse_json` so a malformed page yields null instead of failing the run.
- `job_city` is inconsistent (Arabic, transliteration, airport codes); standardized in intermediate.
- `posting_date_raw` never filled from the relative text (`"27 days ago"`).
- `job_publisher` kept: it sometimes names the original source (e.g. Jooble).

**`stg_jooble_jobs`** — same envelope pattern, array key `jobs`.
- `description_plain` is a snippet, not the full description.
- `posting_date_raw` deliberately null: `updated` is a crawl timestamp, kept as `crawled_at`.
- No structured location and no remote / employment-type signal.
- `underlying_source` kept (e.g. `smartrecruiters.com`): evidence for cross-source matching.

---

## Intermediate layer

The rules, parameters and checks of this layer are described in
[`data_modeling/intermediate_layer.md`](data_modeling/intermediate_layer.md) and
[`data_modeling/data_model.md`](data_modeling/data_model.md).

| Model | Grain | What it does |
|---|---|---|
| `int_landed_files` | One landed file or API page | File-level metadata from RAW: board, pull date, query label, whether the payload is a job list |
| `int_board_pulls` | One pull (ATS board per date; aggregator per date) | Pull calendar: successful pulls only count as evidence; baseline pull |
| `int_source_weeks` | One source per week | Collection coverage for the quality report: whether each source was fully pulled that week (aggregators: the whole baseline campaign repeated) |
| `int_job_listings` | One listing | Union of the six staging models; HTML stripped; city, region, category, company, level and salary standardized; dates in Asia/Riyadh; lifecycle evidence |
| `int_listing_groups` | One listing, with its exact group | Tier 1 matching: normalized title + company + city, publisher rule, rank-to-rank pairing |
| `int_match_candidates` | One candidate pair of exact groups | Guarded fuzzy candidates with Jaccard and Jaro-Winkler scores, no threshold |
| `int_jobs_matched` | One listing, with its job | Tier 2 matching behind `var('fuzzy_match_threshold')` (off while null); `job_sk`, representative listing, `match_tier` |
| `int_job_openings` | One job | Survivorship once; lifecycle: `lifecycle_status`, `opening_date`, `open_until_date`, `disappeared_date`, `days_listed`; parsed salary. Feeds the single fact table `fct_jobs` |
| `int_job_skills` | One job per skill | Skills from `seed_skills` in titles and descriptions of all the job's listings |

Parameters are dbt vars in `dbt_project.yml` (`fuzzy_match_function`, `fuzzy_match_threshold`,
`disappearance_misses`, `recent_window_days`, `aggregator_campaign_coverage`, `business_timezone`).

## Marts layer

A star schema ([`data_modeling/data_model.md`](data_modeling/data_model.md), diagram in `02_code/03_assets/schema_diagram.png`): `fct_jobs` (one job: a job
advertisement in one Saudi location, after cross-source matching) and eight dimensions:
`dim_job_posting`, `dim_company`, `dim_location`, `dim_role` (role family and job category),
`dim_job_attributes`, `dim_date` (role-playing: posted, first seen, last seen, opening, open until,
disappeared), `dim_source` and `dim_skill`, reached through `bridge_job_skill`. Every dimension except
`dim_source` has an Unknown member (`'-1'`); every job has a known source. Columns and tests: `models/marts/schema.yml`. Answers to Q1 to Q9:
`analyses/business_questions.sql`.

## Tests and results

Every model, seed and test runs in `dbt build`. On the final build (2026-09-29, data up to
2026-09-28): 10 seeds, 25 models and 288 data tests, 323 passed, 0 warnings, 0 errors.

- **Keys and grain:** `unique` / `not_null` on every key; `posting_sk` + `location_sk` unique in `fct_jobs`.
- **Vocabularies:** `accepted_values` on employment type, workplace type, remote status, experience level, location level, source type, status basis, lifecycle status, match tier.
- **Referential integrity:** `relationships` on every fact and bridge key, including the six date roles; exactly one Unknown member per dimension except `dim_source` (`tests/generic/has_one_unknown_member.sql`).
- **Reconciliation:** RAW → staging → listings → matched → fact (`tests/assert_*`).
- **Matching:** one representative listing per opening; never two postings of one publisher on one source in one opening; one employer and one location per job; `job_sk` is the earliest listing; a fuzzy job joins exactly two groups.
- **Lifecycle:** `lifecycle_status` is unknown exactly for aggregator-only jobs; a disappeared date exactly for disappeared jobs; an opening date only on the first seen date; a disappeared date after the last employer-board sighting; no employer board's pull may collapse.

RAW-to-staging counts and the layer checks are re-created by `analyses/pipeline_audit.sql` and
`analyses/intermediate_checks.sql` and `analyses/model_checks.sql`; the recorded numbers are in
`data_model.md`, section 10, and are not repeated here.

---

## Team workflow for dbt

### One-time setup (once per machine)

1. Download a copy of the project:
   ```powershell
   git clone https://github.com/RimazKhalid/job-data-pipeline.git
   cd job-data-pipeline\02_code
   ```

2. Install the pinned tools:
   ```powershell
   pip install -r requirements.txt
   ```

3. Connect the project to Snowflake with your own login: copy `dbt/profiles.example.yml` to
   `dbt/profiles.yml` (git-ignored) and put your account, user and password in `02_code/.env`
   (copied from `02_code/.env.example`). Never commit either file.

4. Confirm the role and connection:
   - `JOB_PIPELINE_DEV` must be granted to your user (`snowflake/roles_and_grants.sql`).
   - `profiles.yml` must use `role: JOB_PIPELINE_DEV`, not `ACCOUNTADMIN` or `PUBLIC`.
   ```powershell
   cd 02_src\dbt
   py -m dbt.cli.main debug
   ```
   It should end with "All checks passed!"

### Branching and commits

- **Never push directly to `main`.** Before making any change, create your own branch, named after you:
  ```powershell
  git checkout -b <your-name>
  ```
- Every commit needs a clear message describing what changed, e.g.
  `"Fixed employment_type extraction bug in stg_workable_jobs"`, never `"update"`, `"fix"` or `"changes"`.
  If something breaks later, a clear message shows what changed, when, and who did it.
- After pushing your branch, open a Pull Request on GitHub (**Compare & pull request**), describe
  the change, and **wait for a teammate to review it** before it is merged into `main`.
- After pulling any change into your branch, run `py -m dbt.cli.main deps`, then
  `py -m dbt.cli.main build`, before assuming everything came through intact.

### Quick reference

```powershell
git checkout -b <your-name>          # once, whenever you start a new change
# ... make your code changes ...
git add .
git commit -m "<clear description of what you did>"
git push -u origin <your-name>
# then open a Pull Request on GitHub and wait for review before it's merged into main
```