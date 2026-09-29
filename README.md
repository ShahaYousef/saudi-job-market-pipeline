<!-- README.md -->
# Job Market Data Pipeline, Saudi Arabia (Group A)

SDA Data Engineering Bootcamp capstone, Project 2: Job Market Data Pipeline, scoped to Saudi Arabia.

## Team

| Name | Main responsibilities |
|---|---|
| Rimaz Khalid Alghamdi | Repository owner; Ashby and Workable collection, Snowflake RAW layer, dbt setup and staging, pipeline runner, data-quality checks, curated container and exports |
| Shahd Aldukhayil | Source investigation, architecture, Jooble and JSearch collection, intermediate layer and matching, data model, final repository structure and dashboard |
| Ghadah BaniAli | Greenhouse collection, ADLS Gen2 setup and raw container, Azure Data Factory design |
| Azizah Alharbi | SmartRecruiters collection, source checks, testing and documentation, first Power BI dashboard |

### Contributions

**Rimaz Khalid Alghamdi**
- Built and debugged the Ashby and Workable collection scripts.
- Set up and managed the Snowflake RAW layer for all six sources (warehouse, database, schemas,
  external stage), owned the Snowflake loads, and set up team access for shared development.
- Set up the dbt project (installation, initialisation, Snowflake connection) and built the staging
  models for the six sources (standardisation and light cleaning).
- Co-built the dbt marts layer.
- Unified the project into one repository and managed the Git and GitHub setup and the team workflow.
- Built the one-command pipeline runner (extract, upload, load, freshness, build, export), with a run
  ID and a run log for every execution.
- Ran the final employer-board collection and rebuilt the pipeline end to end on 20,490 listings from
  six sources.
- Expanded the company-alias seed from 37 to 742 reviewed aliases (spelling variants, Arabic names,
  recruitment agencies and job boards), so one employer resolves to one company.
- Implemented the data-quality policy: freshness checks, a guard against collapsed employer-board
  pulls, and layer-to-layer reconciliation from RAW to the fact table.
- Built the `curated` container in ADLS and the export of the marts to it as Parquet, and delivered
  the final datasets as CSV.
- Prepared the final presentation deck.

**Shahd Aldukhayil**
- Source investigation: verified 8 candidate sources one by one (6 employer boards and 2
  aggregators), pulling a real sample from each and documenting its fields and limits before it was
  adopted.
- Architecture: designed the proposal's four-zone pipeline, adopted as the team's blueprint.
- Repository: created the team's first code repository, whose per-source layout (`pipeline/common`,
  `ingestion/<source>`, `probes`, `data_samples`) was reused in the team repository; reorganised the
  final repository into the required submission structure.
- Jooble and JSearch collection: probed the limits of both APIs, then designed the query matrices
  behind 17,721 unique postings (86.5% of all listings), the largest share of the dataset.
- Raw layer: landed every aggregator page unchanged into ADLS, with resumable runs and no failed
  uploads.
- Staging: built the Jooble and JSearch staging models with within-source deduplication; reviewed all
  six staging models, fixed a failing model, added surrogate keys and the first 38 tests, prevented a
  30% loss of Workable data, and fixed a bug that marked 98% of postings closed.
- Intermediate layer: built the 9 intermediate models; cross-source matching turned 20,490 listings
  into 19,148 unique jobs, with 96.1% resolved to city level.
- Data model and marts: redesigned the data model (v3) so all 9 business questions are answerable
  from the fact table, co-built the marts, and wrote the data model document; the final build passes
  288 data tests.
- Final review and dashboard: led the final code review and fixes, and built the final Power BI
  dashboard (8 pages), whose measures reproduce the dbt results in 43 validation checks.

**Ghadah BaniAli**
- Collected job data from the Greenhouse boards.
- Set up the project's Azure Data Lake Storage Gen2 account and built the `raw` container, the
  landing zone every source writes to.
- Set up Azure Data Factory and designed the scheduled pipeline that would run the collection and
  loading steps; the final runs use `run_pipeline.py` on demand.

**Azizah Alharbi**
- Built the Python collection script for the SmartRecruiters boards and organised the extracted data
  in the team's GitHub repository.
- Checked the candidate data sources, performed data-quality testing, and wrote documentation.
- Built the team's first Power BI dashboard connected to Snowflake.

## What we proposed

A repeatable pipeline that finds where Saudi job postings can be collected legally, collects them
from several sources, and turns them into one standardised, deduplicated dataset for job-market
analysis. The proposal is in [`01_proposal/`](01_proposal/).

## What we built

An ELT pipeline on Python, Azure Data Lake Storage Gen2, Snowflake, dbt and Power BI:

- **Six sources:** four employer job boards (Workable, SmartRecruiters, Ashby, Greenhouse) and two
  job aggregators (Jooble, JSearch), chosen from 17 candidates.
- **Raw layer:** every pull landed unchanged in ADLS under `raw/<source>/ingest_date=YYYY-MM-DD/`
  and loaded into Snowflake with `COPY INTO`.
- **dbt:** 6 staging models, 9 intermediate models (standardisation, cross-source matching with an
  exact and a fuzzy tier, job lifecycle, skills) and a star schema of 10 tables, checked by 288
  data tests.
- **Curated dataset:** the ten mart tables, exported to ADLS as Parquet and to
  `02_code/01_data/final_datasets/` as CSV.
- **Dashboard:** an 8-page Power BI report on the marts
  ([`02_code/02_src/powerbi/`](02_code/02_src/powerbi/)).

![Dashboard overview](02_code/03_assets/dashboard_02_overview.png)

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
Job_Market_Data_Pipeline_GroupA_v1/
├── 01_proposal/          Job_Market_Data_Pipeline_GroupA_Proposal_v2.pdf (document)
│                         Job_Market_Data_Pipeline_GroupA_Proposal_Presentation_v1.pdf (slides)
├── 02_code/
│   ├── 01_data/          final datasets (CSV) and sample API responses
│   ├── 02_src/           pipeline, dbt project, Power BI report, Snowflake scripts, probes, source investigation
│   ├── 03_assets/        star schema diagram, dbt lineage, data-quality and dashboard screenshots
│   ├── requirements.txt
│   └── README.md         setup and run instructions
├── 03_project_report/    Job_Market_Data_Pipeline_GroupA_Report_v1.pdf
└── 04_presentation/      Job_Market_Data_Pipeline_GroupA_Presentation_v1.pptx
                          README.md, with the link to the demo video (hosted on Google Drive, over 100 MB)
```
