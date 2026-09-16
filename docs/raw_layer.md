# Raw layer design

How raw data is stored on disk and why, grounded in
`src/common/raw_writer.py` and the `land_raw` functions in
`src/collectors/jooble.py` / `src/collectors/jsearch.py`.

## Partition path

```
raw/<source>/ingest_date=YYYY-MM-DD/<batch_id>__page_NNN.json
```

`ingest_date` is a Hive-style partition: a plain folder name of the form
`ingest_date=2026-09-16`, one per UTC calendar day, taken directly from the
same timestamp used for the envelope's `ingested_at` field
(`raw_writer.write_envelope` receives an `ingest_date = ts[:10]` derived from
that exact timestamp, not a separately-computed "now"). This means every page
landed on the same day lands in the same directory regardless of which
batch, source query, or collector run produced it.

Because a partition directory now holds pages from many different batches
side by side, the page filename carries the `batch_id` as a prefix
(`<batch_id>__page_NNN.json`) to keep them from colliding. Previously the
`batch_id` was the directory name itself; moving it into the filename is
what makes the date-based partition possible at all.

## Envelope format

Every landed page is one JSON file with these top-level fields:

| Field | Meaning |
|---|---|
| `source_id` | `"jooble"` or `"jsearch"` |
| `batch_id` | `<source>__<query_label>__<UTC timestamp>`, identifies the collection run |
| `ingested_at` | UTC ISO timestamp of this specific page fetch (also the source of the partition date) |
| `request` | The exact request that produced this response (see below, differs by source) |
| `http_status` | The HTTP status code received (or `0` for a local/network exception in JSearch) |
| `response_raw` | The full response body, as an unparsed string |

`request` differs between sources because the requests themselves differ:

- Jooble (`POST`, body-based): `endpoint`, `body` (the exact JSON body sent,
  including `page`), `query_hash` (hash of the body), `page`.
- JSearch (`GET`, header-authenticated, retried): `endpoint`, `params` (the
  query string parameters, including `page`), `query_hash`, `page`,
  `attempts` (how many tries `fetch_with_retry` took), `key_index` (which
  key in `API_KEYS` ultimately succeeded or gave up).

One inconsistency worth knowing about, because it is easy to assume
otherwise: `query_hash` in the envelope is a hash of the *page-specific*
request (`body`/`params`, page number included), but `query_hash` written to
`query_log.csv` for the same page is a hash of the *query itself*
(`QUERY`, without the page number). The two hash the same logical query
differently on purpose, one per-page and one per-query, and both collectors
do this identically.

### Real example (Jooble, response_raw truncated)

```json
{
 "source_id": "jooble",
 "batch_id": "jooble__L0_general_sa__20260909T193242Z",
 "ingested_at": "2026-09-09T19:32:43.246380+00:00",
 "request": {
  "endpoint": "POST https://sa.jooble.org/api/{key}",
  "body": { "keywords": "", "location": "Saudi Arabia", "page": 1 },
  "query_hash": "e3462de23bac34b8",
  "page": 1
 },
 "http_status": 200,
 "response_raw": "{\"totalCount\":11524,\"jobs\":[{\"title\":\"Waitress \",...}]}"
}
```

Under the current layout this file would live at
`raw/jooble/ingest_date=2026-09-09/jooble__L0_general_sa__20260909T193242Z__page_001.json`.

## Why the response is a string, not a parsed object

`response_raw` holds exactly the bytes the server returned, decoded as UTF-8
text but never `json.loads`-ed before being written. Both collectors do
parse the response separately, but only to count rows and check IDs for the
run's own console output and logging; that parsed structure is never what
gets written to disk. If the parsing logic here is later found to have a bug
or a schema assumption that turns out to be wrong, the original response is
still intact and can be reprocessed from scratch. Landing an already-parsed
object would bake today's parsing assumptions into the raw layer permanently.

## Why failed responses are landed too

Both `land_raw` functions write the envelope unconditionally, before either
collector inspects `http_status`. A 429, a 500, or a malformed body gets the
same envelope treatment as a 200: the failure itself, including whatever
error body the server sent, is preserved as evidence of what happened during
collection, not silently dropped.

**Fixed 2026-09-16:** landing failures unconditionally used to have a sharp
edge on resume, since `find_existing_page` originally treated any file on
disk as done regardless of its `http_status`. A page that landed with a 429
or a 500 would be skipped forever on every later run of that batch, a
permanent coverage gap that no rerun could heal. `find_existing_page` now
opens the landed file and checks `http_status == 200` before treating it as
complete; see "How resume works at page level" below for the current
behaviour.

## Why duplicates are retained in raw

Both collectors keep a `seen` set of previously-encountered IDs
(`jid`/`job_uid`) loaded from `<source>_seen_ids.json`, but that set is used
**only** to count `new_unique_ids` for the console output and
`query_log.csv`, so the marginal-yield calculation in the matrix runners has
something to divide by. It never filters what gets written: `land_raw`
lands the complete, unmodified `response_raw` regardless of how many of its
records are already in `seen`. A record can appear in raw dozens of times
across different queries and batches. Deduplication is explicitly left for
the curated layer, done there against a deterministic business key
(`id` for Jooble, `job_uid` for JSearch) rather than during ingestion, so the
raw layer stays a faithful record of what each query actually returned.

## How resume works at page level

Before fetching page N, both collectors call
`raw_writer.find_existing_page(RAW_DIR, batch_id, page)`, which globs
`raw/<source>/ingest_date=*/​<batch_id>__page_00N.json` across **every**
date partition, not just the current day's. If a match exists, the page is
skipped with no request made; if not, the page is fetched and landed under
today's partition.

Searching every partition rather than assuming "today" matters because a
batch resumed with `BATCH_ID_OVERRIDE` may have originally landed some pages
on an earlier UTC day. A same-day-only check would re-fetch and re-spend a
request on pages that were already collected, which is exactly the kind of
silent breakage the partitioning change had to avoid.

A landed file only counts as "already done" if it can be opened, parsed as
JSON, and its `http_status` is exactly `200`. If any matching file has a
non-200 status, or can't be parsed at all, `find_existing_page` keeps
looking at the remaining matches and otherwise returns `None`, so the page
gets re-requested and the failed file is overwritten with the new attempt
(same filename, same partition day it's re-landed on, which may differ from
the original failed attempt's day if the rerun happens on a later date).
This closes the gap described above: a page that failed no longer needs a
manual delete to be retried, an ordinary rerun of the batch heals it.
