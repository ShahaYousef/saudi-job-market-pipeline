# pipeline/ — extraction and landing

The code that collects raw job postings from the six sources and lands them in ADLS. It **does not
clean** anything: responses are written as received (apart from the geographic filter noted
below), and all cleaning happens later in dbt.

```
pipeline/
├── common/                 shared modules
│   ├── config.py           landing zone and API keys — used by every script
│   ├── raw_writer.py       envelope files, partitioned path, resume check — aggregators
│   ├── state.py            IDs already seen, across runs — aggregators
│   └── query_log.py        one CSV row per page requested — aggregators
├── ingestion/              one folder per source
│   ├── ashby/ashby.py
│   ├── workable/workable.py
│   ├── greenhouse/greenhouse.py
│   ├── smartrecruiters/smartrecruiters.py
│   ├── jooble/collector.py    jooble/matrix.py
│   └── jsearch/collector.py   jsearch/matrix.py
└── landing/
    └── upload_to_adls.py   mirrors the local landing zone into ADLS
```

Run every command below **from `02_code/02_src`**, after `pip install -r ../requirements.txt`
and filling in `02_code/.env` (copied from `02_code/.env.example`).

---

## The landing zone

Every script writes to one place, defined in `common/config.py`: **`raw/` next to the repo,
outside it**, so raw files can never be committed. Its layout is exactly the one used in ADLS,
by the Snowflake stage and by dbt:

```
<parent folder>/
├── job-data-pipeline/                     the repo
└── raw/
    ├── ashby/ingest_date=YYYY-MM-DD/<board>.json
    ├── workable/ingest_date=YYYY-MM-DD/<account>.json
    ├── greenhouse/ingest_date=YYYY-MM-DD/<board>_jobs.json
    ├── smartrecruiters/ingest_date=YYYY-MM-DD/<company>_jobs.json
    ├── jooble/ingest_date=YYYY-MM-DD/<batch_id>__page_NNN.json
    ├── jsearch/ingest_date=YYYY-MM-DD/<batch_id>__page_NNN.json
    ├── jooble_seen_ids.json               bookkeeping, not uploaded
    ├── jsearch_seen_ids.json              bookkeeping, not uploaded
    └── query_log.csv                      run log, not uploaded
```

`ingest_date` is the UTC date of the pull. Pulling again on another day writes a new
`ingest_date=` folder and never touches an earlier one.

---

## common/

### `config.py` — landing zone and keys

- Resolves every path from its own location: `pipeline/common/` → `pipeline/` → `02_src/` →
  `02_code/` → repository root. The landing zone `raw/` sits next to the repository (outside git);
  `JOB_PIPELINE_RAW_DIR` points it elsewhere.
- Loads `.env` from `02_code/`. `JOOBLE_API_KEYS` / `JSEARCH_API_KEYS` are comma-separated
  when there are several keys; a missing variable stops the run with an explicit error.
- `raw_dir_for(source)` returns `raw/<source>/`, used by all six extraction scripts.

### `raw_writer.py` — landing files (aggregators)

- Every API page is saved as one **envelope**: collection timestamp, batch ID, request
  parameters, HTTP status, and the response body kept as the exact text received
  (`response_raw`). Failed pages are landed too, so every request is traceable.
- **Resumable:** `find_existing_page()` checks every date partition for a page already landed
  with HTTP 200 and skips it. A landed failure counts as not landed, so re-running a batch
  re-requests only what failed — including a batch that crossed UTC midnight.

### `state.py` — seen IDs (aggregators)

A JSON set of the IDs already collected per source (Jooble `id`, JSearch `job_uid`). The
collectors use it to count **new** unique jobs per page, which drives the stopping rule. It is
bookkeeping only: nothing is filtered out because it was seen before.

### `query_log.py` — run log (aggregators)

Appends one row per page to `query_log.csv`: batch, query, page, HTTP status, rows returned,
new unique IDs, cumulative unique IDs, and a truncation flag — the record of how many records
were pulled, when, and by which query.

---

## ingestion/ — aggregators

| File | Role |
|---|---|
| `collector.py` | Runs **one query**: pages through results, lands every page, updates seen IDs and the query log |
| `matrix.py` | Runs a **layer of queries** through the collector and reports the yield (new unique jobs per page) of each |

### Jooble

```powershell
python pipeline/ingestion/jooble/matrix.py <l1|l1b|l1c|l1d|l2|l2b>
```

| Layer | Queries |
|---|---|
| `l1` | One general query per major city |
| `l1b` | Regions and new cities, each checked first with one request: a location Jooble ignores falls back to the general result set and is skipped |
| `l1c` | Locations confirmed by the probes |
| `l1d` | Locations referenced but not yet pulled |
| `l2` | Keywords within Riyadh |
| `l2b` | Keywords within Riyadh whose results hit the page cap, in randomised order |

Collector: up to 50 pages of 20 results, 10 s between pages, stops at the first empty page or
non-200 response.

### JSearch

```powershell
python pipeline/ingestion/jsearch/matrix.py <coverage|kw|temporal>
```

| Layer | Queries |
|---|---|
| `coverage` | Cities, then job titles within Riyadh, as one sequence |
| `kw` | Job titles within Riyadh |
| `temporal` | `date_posted` windows (`today`, `3days`, `week`, `month`) × top locations |

Collector: up to 20 pages, 6 s between pages. On 401 / 403 / 429 it **rotates to the next API
key and retries the same page**; transient 5xx errors are retried up to 3 times. It stops after
2 consecutive empty pages, since a partial page is not a reliable end signal.

**Stopping rule (JSearch):** after each query the matrix computes the mean yield of the last 5
queries and stops the layer when it drops below 2 new unique jobs per page. Query order is
randomised with a fixed seed so the rule is not biased by running the largest queries first.
The Jooble layers print the same yield figures but always run their full list.

---

## ingestion/ — ATS boards

Each script calls one public endpoint per company board, keeps only the Saudi postings, and
writes one file per board. The board list lives in the script; adding a board there is the only
change ever needed between runs.

| Script | Boards configured in | File written |
|---|---|---|
| `ashby/ashby.py` | `JOB_BOARD_NAMES` | `<board>.json` |
| `workable/workable.py` | `WORKABLE_ACCOUNTS` | `<account>.json` |
| `greenhouse/greenhouse.py` | `BOARDS` | `<board>_jobs.json` |
| `smartrecruiters/smartrecruiters.py` | `COMPANIES` | `<company>_jobs.json` |

```powershell
python pipeline/ingestion/ashby/ashby.py
python pipeline/ingestion/workable/workable.py
python pipeline/ingestion/greenhouse/greenhouse.py
python pipeline/ingestion/smartrecruiters/smartrecruiters.py
```

- **A file is written even when a board has no Saudi postings.** An empty file tells dbt the
  board was pulled and has nothing open, so its old postings are marked closed. A board whose
  request fails gets no file and is treated as "not pulled".
- **Geographic filter at extraction.** Ashby, Workable and Greenhouse keep only postings whose
  location matches Saudi keywords; SmartRecruiters filters server-side with `country=sa`. This
  is the one deviation from "no filtering during extraction", done to keep the landed volume to
  the project's scope. dbt re-checks the scope on the structured country field. The Workable script
  also drops postings without a title or a link before saving. Collection has ended, so the
  scripts are kept as they produced the data (data_model.md, section 12).
- **SmartRecruiters** fetches each posting's detail page and adds its `jobAd` (the description
  sections) to the listing record before saving.
- Workable and Greenhouse retry timeouts, connection errors and 5xx responses; SmartRecruiters
  skips a company whose listing request fails.

---

## landing/ — upload to ADLS

```powershell
python pipeline/landing/upload_to_adls.py --dry-run          # list what is new
python pipeline/landing/upload_to_adls.py                    # upload everything new
python pipeline/landing/upload_to_adls.py --source ashby     # one source (repeatable)
```

Mirrors `raw/<source>/ingest_date=*/` into the ADLS container under the same paths, using
`azure-storage-blob` on the account's Blob endpoint — the same endpoint the Snowflake stage reads — and a SAS token scoped to the container. Set in `.env`:
`ADLS_ACCOUNT_NAME`, `ADLS_CONTAINER` (default `raw`) and `ADLS_SAS_TOKEN`. The token needs
**Read, Add, Create, Write and List** — the read-only token used by the Snowflake stage cannot upload.

**Raw is immutable: a file already in ADLS is never overwritten, only skipped.** The one
exception is a 0-byte copy of a non-empty local file — what an interrupted upload leaves behind —
which is replaced and reported as `repaired`. Re-running the upload is always safe. Run it **after** a collection run has finished: the aggregator collectors
re-request failed pages and rewrite them under the same file name, and a failed page that was
already uploaded would not be replaced.

---

## Known limitations

- **Upload is a separate step**, run by hand after extraction — the step an orchestrator (ADF)
  would call after each extraction script.
- **Earlier files kept their original names.** SmartRecruiters files landed before this layout are
  `<company>.json`; newer ones are `<company>_jobs.json`. dbt's `board_from_path()` drops the
  `_jobs` suffix, so both are read as the same board.
- **The Jooble collector** uses the first API key only and stops on the first non-200 response;
  a network error (not an HTTP error) ends the run instead of being recorded as a failed page.