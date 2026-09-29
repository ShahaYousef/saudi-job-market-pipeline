<!-- dbt/data_modeling/aggregator_status.md -->
# Aggregator status: why aggregator-only jobs have no lifecycle

Jooble and JSearch give the pipeline most of its listings, but they cannot say whether a job is
still open. This note explains why, what the evidence is, and how the model handles it. The rule
itself is in `data_model.md`, section 7.1; the counts of each build are in section 10.1.

## 1. Two kinds of sources

| | Employer boards (ATS) | Aggregators |
|---|---|---|
| Sources | Ashby, Greenhouse, SmartRecruiters, Workable | Jooble, JSearch |
| What one pull returns | Every open job on the employer's board | The results of one search: a keyword, a location, a ranking, a page limit |
| Same request on another day | The same board, minus the jobs that closed | A different ranking and a different subset |
| A job missing from the next pull means | The employer took it down | Nothing: it may just not have been returned |

A job that disappears from an employer board is evidence that it was taken down. A job that
disappears from a search result is not.

## 2. The rule

| `status_basis` | `lifecycle_status` | Dates |
|---|---|---|
| `employer board` (the job has at least one ATS listing) | `open` while one ATS listing is still on its board; `disappeared` when every ATS listing is gone after `disappearance_misses` successful pulls of its own board | `disappeared_date_sk` for a disappeared job; `opening_date_sk` for a job no baseline pull saw |
| `aggregator query` (found on Jooble or JSearch only) | `unknown` | No opening date and no disappeared date |

A job found on an employer board and on an aggregator takes the board's status, so an aggregator
copy can never keep a closed job open, and never closes an open one.

## 3. The evidence

- **A search is not a snapshot.** In one Jooble run the reported `total` fell from 13,430 to 12,356
  between page 1 and page 50; a JSearch run stopped at its 20-page cap with new results still
  coming. The same query on another day returns a different set.
- **A recency rule would invent closures.** Marking an aggregator listing closed when it was not
  returned within 7 days of its source's latest run was measured on the listings of 26 September:
  it would have called 89.3% of aggregator listings (9,851 of 11,032) taken down, against 5.2%
  (142 of 2,745) on employer boards, which do show closures. The 1,181 listings it would have kept
  open were exactly the ones the single general query had returned, not the jobs still open.
- **An aggregator copy can outlive the employer's posting.** After the Jooble campaign of
  27–28 September, 20 jobs that had disappeared from their employer's board were still returned by
  Jooble. Employer-board evidence decides: they stay `disappeared`, and
  `assert_job_lifecycle_consistent` compares the disappeared date with the last sighting on an
  employer board (`ats_last_seen_date` in `int_job_openings`).
- **Nothing would have failed.** A status filled in for every row passes `not_null`, so a wrong
  status would have reached `fct_jobs`, the Parquet files in `curated/` and any Power BI card.

## 4. Alternatives considered

| Option | Decision |
|---|---|
| Repeat the whole campaign and read a missing job as closed | Rejected: a repeated search still ranks differently, so a missing job still proves nothing |
| A longer window (e.g. 30 days) | Rejected: only postpones the same error |
| **No status for aggregator-only jobs** | **Chosen.** The model reports status only where there is evidence for it |

## 5. Tests

- `models/marts/schema.yml`: `lifecycle_status` in (`open`, `disappeared`, `unknown`), and
  `unknown` exactly when `status_basis = 'aggregator query'`; a disappeared date exactly for
  disappeared jobs.
- `tests/assert_job_lifecycle_consistent.sql`: no opening date for baseline or aggregator-only jobs;
  a disappeared date after the last employer-board sighting; no job open after the latest
  successful pull.
- `tests/assert_ats_latest_pull_not_collapsed.sql`: stops the build if an employer board's latest
  successful pull holds less than half the postings of its pull before (boards with 10 or more
  postings), so an API change cannot mark a whole board as disappeared.

## 6. Effect on the business questions

Q7 (new openings per week) and Q8 (days listed before disappearing) use employer-board jobs only.
Q1 to Q6 and Q9 count every job, whatever its status, over the observation period.

## 7. Other aggregator limits the model handles

| Issue | Evidence | How the model handles it |
|---|---|---|
| No employer name | Jooble links are redirects and LinkedIn postings are "confidential" | Company `'-1'`, shown as **Employer not disclosed** |
| Overlapping queries return the same job | Jooble 15,010 rows → 8,928 listings and JSearch 3,283 → 2,104 on 26 September | Deduplicated within each source in staging; `copies_landed` keeps the count |
| Aggregators of aggregators | `jobleads.com` is about 40% of Jooble; LinkedIn and Jobrapido about 89% of JSearch | Publisher kept; two listings of one publisher are never merged |
| Missing fields | Jooble has no posting date, employment type or workplace signal; descriptions are snippets | Unknown values shown, and excluded from percentage questions; skill shares use full descriptions only |
| Approximate dates | JSearch derives dates from text such as "10 days ago" | Employer-board posting date is used first |

## 8. Lesson

A value that is filled in and passes `not_null` can still be wrong. For each column the question
is what evidence the source gives for it: an employer board is a full list, so a missing job means
something; a search result is a sample, so it does not. Where there is no evidence, the model says
so (`unknown` and `status_basis`) instead of guessing.
