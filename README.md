<!-- README.md -->
# Saudi Job Market Data Pipeline (Team A)

SDA Data Engineering Bootcamp capstone, Project 2: Job Market Data Pipeline, scoped to Saudi Arabia.

## Team

| Name | Role |
|---|---|
| Rimaz Khalid Alghamdi | Repository owner; ingestion, landing to ADLS, Snowflake setup, exports |
| Ghadah BaniAli | |
| Azizah Alharbi | |
| Shahd Aldukhayil | dbt intermediate layer, cross-source matching, job lifecycle, data model document |

## What we proposed

A repeatable pipeline that finds where Saudi job postings can be collected legally, collects them
from several sources, and turns them into one standardised, deduplicated dataset for job-market
analysis. The proposal is in [`01_proposal/`](01_proposal/).

## What we built

An ELT pipeline on Python, Azure Data Lake Storage Gen2, Snowflake and dbt:

- **Six sources:** four employer job boards (Workable, SmartRecruiters, Ashby, Greenhouse) and two
  job aggregators (Jooble, JSearch), chosen from 17 candidates.
- **Raw layer:** every pull landed unchanged in ADLS under `raw/<source>/ingest_date=YYYY-MM-DD/`
  and loaded into Snowflake with `COPY INTO`.
- **dbt:** 6 staging models, 9 intermediate models (standardisation, cross-source matching with an
  exact and a fuzzy tier, job lifecycle, skills) and a star schema of 10 tables, checked by 288
  data tests.
- **Curated dataset:** the ten mart tables, exported to ADLS as Parquet and to
  `02_code/01_data/final_datasets/` as CSV.

## Results

| Measure | Value |
|---|---|
| Listings collected (after within-source deduplication) | 20,490 |
| Unique jobs after cross-source matching | 19,148 |
| Jobs found on more than one source | 1,008 (5.3%) |
| Employer-board jobs open / disappeared | 2,584 / 177 |
| New openings seen after the first pull | 174 |
| Final dbt build | 323 checks passed, 0 warnings, 0 errors |

The business questions, the data quality report and every measured limitation are in the data
model document, [`02_code/02_src/dbt/data_modeling/data_model.md`](02_code/02_src/dbt/data_modeling/data_model.md).

## How to run it

Setup, keys, run commands and known issues: [`02_code/README.md`](02_code/README.md).

## Folder structure

```
Saudi_Job_Market_Data_Pipeline_Team_A_v1/
├── 01_proposal/          project proposal (PDF)
├── 02_code/
│   ├── 01_data/          final datasets (CSV) and sample API responses
│   ├── 02_src/           pipeline, dbt project, Snowflake scripts, probes, source investigation
│   ├── 03_assets/        star schema diagram, dbt lineage, screenshots
│   ├── requirements.txt
│   └── README.md         setup and run instructions
├── 03_project_report/    Saudi_Job_Market_Data_Pipeline_Team_A_Report_v1.pdf
└── 04_presentation/      Saudi_Job_Market_Data_Pipeline_Team_A_Presentation_v1.pptx
                          Saudi_Job_Market_Data_Pipeline_Team_A_DemoVideo_v1.mp4
```
