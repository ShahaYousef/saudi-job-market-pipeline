# Collection methodology

How the Jooble and JSearch collectors work, and why they were built this way.
Every claim below is grounded in `pipeline/ingestion/jooble/collector.py`,
`pipeline/ingestion/jsearch/collector.py` and `pipeline/ingestion/*/matrix.py`
as they exist in this repo.

## Why both sources are query-scoped

Neither API has a "list everything" endpoint. Jooble requires a `location`
(and optional `keywords`) in every request body; JSearch requires a `query`
string that embeds the search terms (`"jobs in Riyadh"`, `"welder jobs in
Riyadh"`). There is no way to ask either source for its full Saudi Arabia
inventory in one call. Coverage is therefore entirely a function of how many
distinct queries you run and how you choose them, not of how many pages you
are willing to paginate through on a single query. This is why the bulk of
the collection design (the matrix runners) is about query selection, not
about the fetch loop itself.

## Jooble: the 1000-record ceiling

`jooble.py` sets `MAX_PAGE = 50` and `PAGE_SIZE = 20`. 50 pages of 20 rows is
a hard ceiling of 1000 records per query, regardless of how many jobs
actually match. The collector detects this in the log: `truncated_flag` is
set when `page == MAX_PAGE and rows == PAGE_SIZE`, meaning page 50 still came
back full, so the query was cut off while data was still available.

Because the ceiling applies per query, not per account, `jooble_matrix.py`
partitions the search space to keep each individual query's result set under
1000:

- **l1 / l1b / l1c / l1d** partition by location: an initial set of major
  cities, then a pre-flight-guarded batch of additional regions, then a
  larger set of probed locations (one of which, Al Dhahran, is deliberately
  capped at 5 pages because it was suspected to duplicate Khobar), then a
  handful of locations that had been referenced but never pulled.
- **l2 / l2b** partition by job title within Riyadh specifically, because
  the unfiltered Riyadh query alone is large enough to hit the ceiling on
  its own. Adding a keyword narrows the result set back under 1000.

Each (location) or (location, keyword) pair is run as its own batch with its
own `QUERY_LABEL`, so the 1000-record ceiling is worked around by never
asking a question broad enough to exceed it, rather than by trying to defeat
the ceiling directly.

## JSearch: no total count, so the axis has to be found empirically

JSearch's response has no `totalCount`-equivalent field anywhere.
`jsearch.py`'s `land_raw` always logs `total_count_reported: None`. Without a
window size, there is no way to know in advance whether a query has 5
results or 5000, or whether paging further will keep returning new records.

Location and job-title queries against JSearch saturate almost immediately
(this is stated directly in `jsearch_matrix.py`'s `run_coverage`, which notes
it "maximises coverage" but leaves freshness to a separate mechanism). The
axis that measured 100% novelty, per the comment in `run_temporal`, is
`date_posted` (`today`, `3days`, `week`, `month`): because JSearch re-ranks
its entire result set differently for each value rather than simply
filtering it, each `date_posted` value exposes a different slice of the same
underlying data instead of a strict subset. That is why `jsearch_matrix.py`
crosses `date_posted` against the top geographies as its own dedicated
layer (`run_temporal`), separate from the plain city/keyword coverage layer.

## Pre-flight probes and their verdicts

Before spending a full multi-page pull on a candidate query, several scripts
send one request and read the verdict before deciding whether to proceed.
The pattern differs slightly by script, but the logic is always: one
request, classify, then either skip or commit.

In `jooble_matrix.py`'s `l1b` layer (`_l1b_preflight`), a location is
skipped if:
- the request fails (non-200), or the body is not valid JSON,
- it returns zero jobs, or
- `totalCount >= 10000` (`GENERAL_BASELINE`). This threshold exists because
  Jooble silently falls back to its full, unfiltered result set when it
  does not recognise a location string, rather than returning an error. A
  `totalCount` at or above the general-query scale is the signature of that
  fallback, meaning the location parameter was effectively ignored.

The standalone probe scripts (`probes/jooble_probe_locations.py`,
`probes/jooble_probe_keywords.py`) used the same "location/keyword ignored"
signal to build the candidate lists before the matrix ever ran, with an
additional `"capped"` verdict in the keyword probe (`totalCount > 1000`)
flagging keywords that would themselves hit the 1000-record ceiling if
pulled in full.

## The marginal yield stopping rule

The rule as designed: track new unique records divided by pages spent for
each query, average that yield over the last 5 queries, and stop expanding
an axis once that average drops below 2.0.

**This is only actually enforced in the JSearch matrices.** All three layers
in `pipeline/ingestion/jsearch/matrix.py` (`run_coverage`, `run_kw`, `run_temporal`)
compute the trailing 5-query mean after every query and `break` out of the
loop the moment it falls below 2.0, printing `STOPPING RULE MET`.

In `pipeline/ingestion/jooble/matrix.py`, the rule is **not enforced as a break in
any of the six layers**:
- `l1`, `l1b`, `l1c`, `l1d` never compute a rolling yield at all; they run
  their full target list every time regardless of yield.
- `l2` computes the mean yield of the *last 5* keywords, but only after the
  loop over all 18 keywords has already finished, and only prints it.
- `l2b` computes the mean yield across *all* keywords in its list (not just
  the last 5), again only after the loop has finished, and only prints it.

So on the Jooble side, the 2.0 threshold functioned as a post-hoc read on
whether an axis was worth extending in a future run, not as an automatic
cutoff. If your review or presentation describes the stopping rule as
uniformly enforced across both sources, that would not match what the code
does; flag it if that matters for how the methodology is presented.

Where randomisation is used to keep the yield calculation from being biased
by query ordering, it is seeded: `jooble_matrix.py`'s `l2b` and every layer
in `jsearch_matrix.py` call `random.seed(42)` before shuffling their keyword
or query lists, so the run order (and therefore the yield curve) is
reproducible.

## Why the two collectors differ

| | Jooble | JSearch |
|---|---|---|
| Method | `POST`, key embedded in the URL path (`/api/{key}`) | `GET`, key in the `x-api-key` header |
| Total count | Returned (`totalCount`), used to detect the ceiling and the "ignored" fallback | Never returned; window size is unknowable |
| Empty-page stop | Stops on the **first** empty page | Stops after **2 consecutive** empty pages (`STOP_AFTER_EMPTY = 2`), because a single empty page is not treated as reliable evidence the source is exhausted |
| Key rotation | None; always uses `API_KEYS[0]` even if more keys are configured | Rotates to the next key on `401/403/429` and retries the *same* request, so a quota event never causes a skipped page |
| Retry on transient failure | None; any non-200 response stops the whole run immediately ("non-200 received, stopping. Inspect the landed file.") | Retries up to `MAX_RETRIES = 3` with a 15s backoff on any status that isn't 200, a quota code, or a 4xx client error, i.e. 5xx responses and local/network exceptions (which `_raw_call` reports as status `0`) |

These aren't arbitrary: Jooble's ceiling and `totalCount` make it possible to
detect truncation and plan queries around it, so the collector can afford to
be strict and stop at the first sign of trouble. JSearch gives no such
signal, so its collector is built to tolerate more noise (retry transient
errors, rotate quota-exhausted keys, wait for two empty pages) before
concluding a query is actually done.
