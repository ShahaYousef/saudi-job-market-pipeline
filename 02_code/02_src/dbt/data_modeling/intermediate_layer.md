<!-- dbt/data_modeling/intermediate_layer.md -->
# Intermediate layer

The intermediate layer turns the six staging models into one standardized set of listings, matches
the listings of one job across sources, and prepares what the marts need: one row per job for the
single fact table (star schema), the job lifecycle, the skills, and the evidence for the data quality
report. Every model is
a table in the `INTERMEDIATE` schema.

## Lineage

```
RAW ──► int_landed_files ──► int_board_pulls ──┐
            │                                  │
            └──────────► int_source_weeks (collection coverage, quality report)
                                               ▼
stg_* (6) ──────────────────────────► int_job_listings
                                               │
                                      int_listing_groups
                                               │
                                      int_match_candidates
                                               │
                                      int_jobs_matched ──► int_job_skills
                                               │
                                      int_job_openings ──► fct_jobs (one fact table: star schema)
```

`int_landed_files` is the only intermediate model that reads RAW, and it reads file-level metadata
only (file name, collection time, HTTP status, whether the payload is a job list). Staging flattens
files into postings, so a pull that failed or returned nothing leaves no trace there.

## Rules

| Area | Rule | Model |
|---|---|---|
| Dates | Converted to Asia/Riyadh before the date is taken; weeks run Sunday to Saturday | all |
| Pull evidence | A pull is successful when its payload is a job list. ATS: a jobs array, empty included; an error body is not. Aggregators: HTTP 200 with a parseable body | `int_landed_files`, `int_board_pulls` |
| Baseline | The first successful pull of an ATS board, or the first collection week of an aggregator. Its contents existed before the pipeline looked, so they are never new openings | `int_board_pulls` |
| Full pull | ATS: any successful board pull. Aggregator: the week repeats the baseline campaign's queries (`aggregator_campaign_coverage`, 1.0 = all) | `int_source_weeks` |
| Location | City field first, then location text. A hit inside a longer hit is part of it ("makkah" in "makkah province"). A text naming several cities keeps the region they share, else country | `int_job_listings` |
| Level | Source field first; else a title word from `seed_seniority_keywords`; else Unknown. `experience_level_basis` says which | `int_job_listings`, `int_job_openings` |
| Salary | Parsed when the text follows `currency amount[ - amount] per period`; converted to SAR per month for month, week and year; hour and day are not converted | `int_job_listings` |
| Disappearance | An ATS listing staging marks inactive, confirmed by `disappearance_misses` successful pulls of its own board. A failed pull confirms nothing | `int_job_listings` |
| Exact match | Same `title_norm`, `company_norm`, `city_std`; two postings that one publisher lists on one source are never merged; one publisher's postings on one source are paired rank to rank | `int_listing_groups` |
| Fuzzy match | Two exact groups of one company and city, with no publisher shared on one source and the same level words, merged when the score reaches the threshold and each is the other's best candidate. Off while `fuzzy_match_threshold` is null | `int_match_candidates`, `int_jobs_matched` |
| Survivorship | Representative listing by `source_priority`, which also gives the description; first known value by priority for attributes; the source's level before a title level | `int_job_openings` |
| Lifecycle | `disappeared` when every ATS listing disappeared; `open` when one is still on its board; `unknown` for aggregator-only jobs | `int_job_openings` |
| New openings | `opening_date` is set only for a job with an ATS listing that no baseline pull saw. An aggregator-only job never gets one: a query result is a ranked slice, so first appearing in a later campaign is no more evidence of a new opening than disappearing is of a closure. On the 27 September build, 773 of the 923 jobs outside the baseline were aggregator-only | `int_job_openings` |
| Open interval | From `first_seen_date` to `open_until_date`: the day before disappearance, else the latest evidence plus `recent_window_days`, never after the latest successful pull. A job is open during a period when `first_seen_date` <= period end and `open_until_date` >= period start | `int_job_openings` |
| Collection coverage | Which sources were fully pulled in each week, so a change between periods is read against it | `int_source_weeks` |
| Skills | Whole-word match of `seed_skills` on titles and descriptions of all listings of the job | `int_job_skills` |

## Parameters (`dbt_project.yml`)

| Var | Value | Status |
|---|---|---|
| `business_timezone` | `Asia/Riyadh` | Decided |
| `fuzzy_match_function` | `jaccard` | Chosen from 88 labelled pairs (data_model.md, section 8.7) |
| `fuzzy_match_threshold` | 80 | Precision 0.917, in-sample recall 0.579 when chosen; 0.833 and 0.357 on the pairs still candidates after the review fixes; null turns the fuzzy tier off |
| `disappearance_misses` | 1 | None of the 2,769 ATS listings reappeared after missing a pull of its board |
| `recent_window_days` | 7 | The weekly collection schedule |
| `aggregator_campaign_coverage` | 1.0 | Definition of a full campaign |

## Choosing the fuzzy threshold

1. Build the layer, then run `analyses/fuzzy_review_sample.sql`. It returns up to 10 candidate pairs
   from every 10-point band of each score, from 50 to 100.
2. Label each pair in `seeds/seed_match_review.csv` (`listing_a,listing_b,is_same_job,reviewer`) and
   run `dbt seed --select seed_match_review`.
3. Run `analyses/match_threshold_evaluation.sql`. It gives precision and in-sample recall for every
   threshold from 50 to 100, for both scores.
4. Set `fuzzy_match_function` and `fuzzy_match_threshold`, rebuild, and report the threshold with its
   precision, recall and number of labelled pairs.
5. Run `analyses/fuzzy_merge_audit.sql` and check every merge the tier made. Final build: Jaccard at 80,
   20 merges, 18 the same job by title (data_model.md, section 8.7). `analyses/match_label_status.sql`
   shows which labelled pairs are still candidates after a change to the title key.

A test build on the repository's samples showed why the choice needs labels: Jaro-Winkler scored
different Qiddiya jobs that share the prefix "Assistant Manager -" at 86 to 93
("Assets Infrastructure Delivery" / "Asset Infrastructure Design": 93), while their Jaccard score
stayed at 43 or below.

## Seeds added

| Seed | Rows | Evidence |
|---|---|---|
| `seed_seniority_keywords` | 9 | Measured on the 1,510 postings whose source gives a level (26 September export). A word is kept when those postings agree with it at least 70% of the time: director 72%, intern 100%, senior 74%, lead 73%, leader 82%, manager 81%. "Assistant manager" (45%) blocks the manager rule. Left out: junior 40%, trainee 44%, consultant 64%. Together the rules agree with the source 78% of the time. On the final build the level is known for 39.1% of jobs, 9.4% from the source alone |
| `seed_skills` | 133 keywords, 125 skills | Terms found in at least 10 of the 4,304 postings with a full description. Ambiguous words left out: sales, kpi, hospitality, tax, lean, soc, iam, swift, react, vulnerability, .net, c# |
| `seed_currency_rates` | 2 | SAR 1; USD 3.75 (the riyal's peg) |
| `seed_match_review` | 0 | Filled by the manual review |

## Checks

- `dbt build --select intermediate` runs the model tests in `models/intermediate/schema.yml` and the
  singular tests in `tests/`: listings kept, publisher rule, one representative per job, job
  survivorship, fuzzy merges keep level words, lifecycle consistency, multi-city texts without a
  city, valid salary amounts and conversion, collapsed board pulls.
- `analyses/intermediate_checks.sql` returns the layer's numbers in one result set for the quality
  report: listings and jobs, match tiers, location levels, level basis, salaries parsed, lifecycle,
  baseline and new jobs, failed pulls, sources fully pulled per week, skill coverage.
