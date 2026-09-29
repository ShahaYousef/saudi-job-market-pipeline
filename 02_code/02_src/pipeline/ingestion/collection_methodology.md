<!-- pipeline/ingestion/collection_methodology.md -->
# Collection methodology

How the six extraction scripts collect job postings, and why each family of sources is collected
differently. Every statement below refers to the scripts in `pipeline/ingestion/` and
`pipeline/common/` as they exist in this repo. Source selection (which sources, and why) is in
[`../../source_investigation/source_investigation.md`](../../source_investigation/source_investigation.md).

| Family | Sources | One request returns | Scripts |
|---|---|---|---|
| **Employer job boards (ATS)** | Ashby, Greenhouse, SmartRecruiters, Workable | One company's whole board | `ashby/ashby.py`, `greenhouse/greenhouse.py`, `smartrecruiters/smartrecruiters.py`, `workable/workable.py` |
| **Aggregators** | Jooble, JSearch | One search query (keywords and location) | `jooble/collector.py`, `jsearch/collector.py` (one query); `jooble/matrix.py`, `jsearch/matrix.py` (the campaign) |

The difference matters beyond collection: a board file lists **every** open job of a company, so
a job missing from the next collection was taken down. A query returns only what matched that
query on that day, so a job missing from a different query proves nothing (Section 5).

---

## 1. What every script has in common

- **Raw landing zone outside the repo.** Every file is written under `<raw>/<source>/ingest_date=YYYY-MM-DD/`
  (`config.raw_dir_for`), with `ingest_date` as the UTC date of the run. Raw data never enters git.
  An ATS file carries no other time, so a pull made between 00:00 and 03:00 Riyadh time is dated
  the day before (data_model.md, section 12). Aggregator envelopes carry `ingested_at`, which dbt
  converts to Riyadh time.
- **Append-only.** A file is never edited after it lands. `landing/upload_to_adls.py` copies new
  files to ADLS (`stjobdata26/raw/`) and never overwrites one already there; `dbt run-operation
  load_raw` then runs `COPY INTO` for new files only.
- **Kept as received.** Scripts may filter which postings to keep, but never rename or reshape a
  field. All cleaning happens in dbt staging.
- **Every run is logged.** ATS scripts write one row per board to `<raw>/extract_log.csv`;
  aggregator scripts write one row per page to `<raw>/query_log.csv`. `pipeline/run_pipeline.py`
  gives every run a `run_id` and writes one row to `<raw>/run_log.csv`.

## 2. Employer job boards (ATS)

### 2.1 How a board is pulled

| Source | Endpoint (public, no key) | Saudi filter | Pagination | Description |
|---|---|---|---|---|
| Ashby | `GET api.ashbyhq.com/posting-api/job-board/<board>` | In the script: `SAUDI_KEYWORDS` against `location`; staging re-checks the country (a substring match such as `hail` also matches `Thailand`) | None, whole board | In the response. Salary bands are off (`includeCompensation=false`) |
| Greenhouse | `GET boards-api.greenhouse.io/v1/boards/<board>/jobs?content=true` | In the script: `SAUDI_KEYWORDS` against `location`. The 9 September files were not filtered; staging removes their 24 non-Saudi postings | None, whole board | In the response (HTML) |
| SmartRecruiters | `GET api.smartrecruiters.com/v1/companies/<company>/postings?country=sa` | **By the API** (`country=sa`), the only server-side filter among the six sources | `offset` / `limit=100` until an empty page | One detail request per posting, adding its `jobAd` |
| Workable | `GET apply.workable.com/api/v1/widget/accounts/<account>?details=true` | In the script: the structured `country` / `countryCode` fields; keyword matching only when both are missing. Postings without a title or a link are dropped | None, whole account | In the response (`details=true`) |

Boards were found by hand (no ATS publishes its client list): a web search for each platform's
job-page pattern, keeping the boards that returned Saudi postings. The board lists are at the top
of each script; adding a board is the only edit needed between runs.

### 2.2 Failures

All four scripts fetch through `common/http_retry.get_json`:

- timeouts, connection errors, HTTP 429 and 5xx are retried up to 3 times, waiting 5, 10 and 20
  seconds, or the server's `Retry-After` (at most 120 seconds);
- HTTP 404 is not retried: the board does not exist;
- a board that still fails is logged as `failed` in `extract_log.csv` and gets **no file**, so the
  pipeline treats it as "not pulled", never as "every job closed". The other boards are still
  collected; a script exits with an error only when every board failed.

A board that is pulled but has no Saudi posting still gets a file with an empty list, so "pulled,
nothing open" is distinguishable from "not pulled".

### 2.3 What each file records

One JSON file per board per run, named after the board. `extract_log.csv` records, per board:
`run_id`, source, board, `ingest_date`, extraction time, outcome, HTTP status, jobs returned, jobs kept (Saudi),
file path, the file's SHA-256 and any error, so a landed file can be checked against the run that wrote it.

### 2.4 Collections so far

| Source | Boards | Collections (UTC) |
|---|---|---|
| Ashby | 10 | 16, 24, 25, 27 and 28 September 2026 |
| Greenhouse | 17 | 9, 24, 25, 27 and 28 September 2026 |
| SmartRecruiters | 14 | 19, 24, 25, 27 and 28 September 2026 |
| Workable | 11 | 16, 24, 25, 27 and 28 September 2026 |

## 3. Aggregators: why both sources are query-scoped

Neither API has a "list everything" endpoint. Jooble requires a `location` (and optional
`keywords`) in every request body; JSearch requires a `query` string that embeds the search terms
(`"jobs in Riyadh"`, `"welder jobs in Riyadh"`). There is no way to ask either source for its full
Saudi Arabia inventory in one call. Coverage is therefore a function of how many distinct queries
are run and how they are chosen, not of how many pages are paginated on a single query. This is
why most of the collection design (the matrix runners) is about query selection, not about the
fetch loop itself.

Each query is one batch with its own `QUERY_LABEL`, and every page lands as an envelope that keeps
the request (`body` or `params`, `page`, `query_hash`), the HTTP status and the raw response, so
any query can be identified and repeated from RAW alone.

### 3.1 Jooble: the 1,000-record ceiling

`jooble/collector.py` sets `MAX_PAGE = 50` and `PAGE_SIZE = 20`: a hard ceiling of 1,000 records
per query, however many jobs match. The collector detects it in the log: `truncated_flag` is set
when `page == MAX_PAGE and rows == PAGE_SIZE`, meaning page 50 still came back full, so the query
was cut off while data was still available.

Because the ceiling applies per query, not per account, `jooble/matrix.py` partitions the search
space to keep each query's result set under 1,000:

- **l1 / l1b / l1c / l1d** partition by location: an initial set of major cities, then a
  pre-flight-guarded batch of additional regions, then a larger set of probed locations (one of
  which, Al Dhahran, is deliberately capped at 5 pages because it was suspected to duplicate
  Khobar), then a handful of locations that had been referenced but never pulled.
- **l2 / l2b** partition by job title within Riyadh, because the unfiltered Riyadh query alone is
  large enough to hit the ceiling. Adding a keyword narrows the result set back under 1,000.

The ceiling is worked around by never asking a question broad enough to exceed it, rather than by
trying to defeat it.

### 3.2 JSearch: no total count, so the axis has to be found empirically

JSearch's response has no `totalCount` equivalent; `jsearch/collector.py` always logs
`total_count_reported: None`. There is no way to know in advance whether a query has 5 results or
5,000, or whether further pages will keep returning new records.

Location and job-title queries saturate almost immediately (stated in `run_coverage` of
`jsearch/matrix.py`, which maximises coverage but leaves freshness to a separate layer). The axis
that measured 100% novelty, per the comment in `run_temporal`, is `date_posted` (`today`,
`3days`, `week`, `month`): JSearch re-ranks its whole result set for each value rather than
filtering it, so each value exposes a different slice of the same data instead of a strict
subset. `jsearch/matrix.py` therefore crosses `date_posted` with the top geographies as its own
layer (`run_temporal`), separate from the city and keyword coverage layers.

### 3.3 Pre-flight probes and their verdicts

Before a full multi-page pull, several scripts send one request, classify it, then either skip or
commit.

In `jooble/matrix.py`'s `l1b` layer (`_l1b_preflight`), a location is skipped if:

- the request fails (non-200) or the body is not valid JSON,
- it returns zero jobs, or
- `totalCount >= 10000` (`GENERAL_BASELINE`). Jooble silently falls back to its full, unfiltered
  result set when it does not recognise a location string, rather than returning an error; a
  `totalCount` at the general-query scale is the signature of that fallback.

The standalone probes (`probes/jooble/jooble_probe_locations.py`, `probes/jooble/jooble_probe_keywords.py`) used
the same "location or keyword ignored" signal to build the candidate lists before the matrix ran,
with an extra `capped` verdict in the keyword probe (`totalCount > 1000`) for keywords that would
themselves hit the 1,000-record ceiling.

### 3.4 The marginal-yield stopping rule

The rule as designed: track new unique records per page spent for each query, average that yield
over the last 5 queries, and stop expanding an axis once the average drops below 2.0.

**It is enforced only in the JSearch matrix.** All three layers of `jsearch/matrix.py`
(`run_coverage`, `run_kw`, `run_temporal`) compute the trailing 5-query mean after every query and
stop the loop when it falls below 2.0, printing `STOPPING RULE MET`.

In `jooble/matrix.py` the rule is **not enforced as a stop in any of the six layers**:

- `l1`, `l1b`, `l1c`, `l1d` do not compute a rolling yield; they run their full target list.
- `l2` computes the mean yield of the last 5 keywords only after all 18 keywords have run, and
  only prints it.
- `l2b` computes the mean yield across all its keywords, again only after the loop, and only
  prints it.

On the Jooble side the 2.0 threshold was a read-out for deciding whether to extend an axis in a
later run, not an automatic cut-off. Descriptions of the method should say so.

Where query order is shuffled to keep the yield curve from depending on it, the shuffle is seeded:
`jooble/matrix.py`'s `l2b` and every layer of `jsearch/matrix.py` call `random.seed(42)`, so the run
order, and the yield curve, are reproducible.

### 3.5 Why the two collectors differ

| | Jooble | JSearch |
|---|---|---|
| Method | `POST`, key in the URL path (`/api/{key}`) | `GET`, key in the `x-api-key` header |
| Total count | Returned (`totalCount`); used to detect the ceiling and the "ignored" fallback | Never returned; the result size is unknowable |
| Empty-page stop | Stops on the **first** empty page | Stops after **2 consecutive** empty pages (`STOP_AFTER_EMPTY = 2`): one empty page is not treated as proof the query is exhausted |
| Key rotation | None: always `API_KEYS[0]`, even when more keys are configured | Rotates to the next key on 401 / 403 / 429 and retries the **same** request, so a quota event never skips a page |
| Transient failures | Not retried: any non-200 stops the run ("non-200 received, stopping. Inspect the landed file.") | Retried up to `MAX_RETRIES = 3` with a 15 s back-off for 5xx and network errors (reported by `_raw_call` as status `0`) |
| Quota | 500 requests per key, lifetime | Per key, per month |

Jooble's ceiling and `totalCount` make truncation detectable, so its collector can stop at the
first sign of trouble. JSearch gives no such signal, so its collector tolerates more noise before
it concludes that a query is done.

### 3.6 Collections so far

| Source | Campaign | Later runs |
|---|---|---|
| Jooble | 9–10 September 2026 (UTC): the location layers, then the Riyadh keyword layers | 26 September: the general query `L0_general_sa` only. 27 September: the whole campaign repeated, every baseline query label (seen file reset first; locations that timed out re-run with `jooble/rerun_locations.py`) |
| JSearch | 10–12 September 2026 (UTC): `L0`, then the coverage and `date_posted` layers | 26 September: `L0_general_sa` only. 27–28 September: the whole campaign repeated, every baseline query label. The matrix run stopped when all keys returned 429; the missing labels were run by name with `jsearch/rerun_queries.py`, split across two team members' keys |

**Week of 27 September.** Every baseline query of both aggregators was repeated, so this is the
first week in which all six sources were fully pulled (`int_source_weeks`; `data_model.md`,
section 10.2). JSearch pages that answered 429, 403 or 504 are landed as failed pages (101 in RAW)
and carry no rows; each affected label was re-requested under a new batch.

## 4. Running a collection

`pipeline/run_pipeline.py` runs the four ATS scripts by default, then upload, load, freshness,
build and export. The aggregators run only when named, because of their quotas:

    py pipeline/run_pipeline.py                                      # ATS boards, then everything after
    py pipeline/run_pipeline.py --sources jooble jsearch             # adds the aggregators' collector.py
    py pipeline/run_pipeline.py --steps upload load freshness build export   # files already collected

`--sources jooble jsearch` runs `collector.py`, which holds **one** query (`QUERY`,
`QUERY_LABEL = "L0_general_sa"`). The campaign's layers run only through `jooble/matrix.py` and
`jsearch/matrix.py`. The collectors take no command-line options: any argument, including
`--help`, is ignored and starts a real collection.

## 5. Repeating the aggregator campaign, and what it can show

A job missing from a later ATS collection was taken down: the board lists every open job. For an
aggregator, a job missing from a later run shows nothing unless **the same query** was repeated,
and even then ranking changes between days. The campaign was repeated in full on 27–28 September,
and still a repeated search returns a different ranking and subset, so a listing missing from it
proves nothing. For this reason aggregator-only jobs have `lifecycle_status = 'unknown'` (`data_model.md`, section 7.1),
and closures are counted from employer boards only.

Repeating the campaign adds listings and freshness, not status. To repeat it, run the matrix
runners with the same `QUERY_LABEL`s and query bodies, and check before starting:

1. **Quota.** The Jooble campaign used about 770 requests, more than one key's lifetime quota;
   count the pages per `QUERY_LABEL` in RAW (`raw_jooble`, `raw_jsearch`) and make sure the keys in
   `.env` cover them. Jooble's collector does not rotate keys. A JSearch key holds about 200
   requests; the whole campaign needs several keys from separate accounts (a new key in the same
   account shares its quota, and a key must be subscribed to JSearch or it answers 403).
2. **Resuming.** When a run stops on quota or a timeout, re-run only the missing labels:
   `py pipeline/ingestion/jsearch/rerun_queries.py <label> ...` (same query bodies as `matrix.py`,
   no stopping rule) or `py pipeline/ingestion/jooble/rerun_locations.py <prefix> <location> ...`.
3. **The `seen` file.** `new` and `cum_unique` in the console are counted against the local
   `seen` state of the machine that runs the collector. They do not affect what lands in RAW.
4. **Landing.** After the run: `py pipeline/run_pipeline.py --steps upload load freshness build export`.