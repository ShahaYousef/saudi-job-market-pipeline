<!-- source_investigation/source_investigation.md -->
# Source Investigation — Job Market Data Pipeline (Saudi Arabia)

Which job-data sources were evaluated, which were selected or excluded and why, and what the
selected sources turned out to contain once collected.

| | |
|---|---|
| **Candidates evaluated** | 17: 8 with a usable API, 9 excluded for legal or access reasons |
| **Selected and collected** | 6: four ATS job boards (Ashby, Greenhouse, SmartRecruiters, Workable) and two aggregators (Jooble, JSearch) |
| **Investigation dates** | 31 August – 2 September 2026 (probes), updated with collection results on 28 September 2026 |
| **Collected listings** | 20,490 unique listings after within-source deduplication (final build, 28 September) |

Related files:

| File | Content |
|---|---|
| `source_investigation.md` | This summary: decisions, collection results, and how the findings shaped the pipeline |
| [`../pipeline/ingestion/collection_methodology.md`](../pipeline/ingestion/collection_methodology.md) | How each source is collected: endpoints, filters, retries, query layers, quotas |

The Jooble and JSearch probe scripts are in [`../probes/`](../probes/).

---

## 1. Evaluation criteria

Each candidate was checked against the same questions before any collection code was written:

1. **Legal access.** Does the source offer a public API, or do its terms of use and `robots.txt`
   prohibit automated collection?
2. **Saudi coverage.** Does it return Saudi job postings, and can they be filtered to Saudi Arabia
   reliably?
3. **Useful fields.** Company, title, location, posting date, employment type, description.
4. **Stable identifier.** A key that identifies the same posting across repeated collections.
5. **Limits.** Authentication, rate limits, request quotas, result caps.

Each source was probed with real requests; the decision per source is in Section 2.

---

## 2. Decision summary

| Source | Type | Access | Decision | Reason |
|---|---|---|---|---|
| Ashby | ATS job board | Public REST API, no key | ✅ Collected | Real posting date, structured address, remote flag; best access reliability once requests are sent one board at a time |
| Greenhouse | ATS job board | Public REST API, no key | ✅ Collected | Company name and real posting date in every record; boards found manually |
| SmartRecruiters | ATS job board | Public REST API, no key | ✅ Collected | Only source with a working server-side country filter (`country=sa`); richest structured location; experience level and industry |
| Workable | ATS job board | Public widget API, no key | ✅ Collected | High Saudi share on Saudi accounts; experience level, industry, employment type |
| Jooble | Aggregator | REST API, free key | ✅ Collected | Largest volume; reaches platforms outside the team's ATS coverage (93% of its records) |
| JSearch (OpenWeb Ninja) | Aggregator | Commercial API, free tier | ✅ Collected | Full descriptions, publisher field, employment type; surfaces LinkedIn and other boards through Google for Jobs |
| Lever | ATS job board | Public REST API, no key | ⚪ Tested, not collected | Only 3 of 9 tested boards answer through the API (the rest return an account-level 404), for 14 Saudi postings. Lever postings still reach the dataset through Jooble (27 records) |
| Recruitee | ATS job board | Public REST API, no key | ⚪ Tested, not collected | One board tested (17 Saudi postings). Recruitee postings still reach the dataset through Jooble (269 records) |
| LinkedIn | Job site | Web pages only | ❌ Excluded | Terms of use and `robots.txt` prohibit automated collection (checked directly) |
| Indeed | Job site | Web pages only | ❌ Excluded | Terms of use prohibit automated collection |
| GulfTalent | Job site | Web pages only | ❌ Excluded | Terms of use prohibit automated collection |
| NaukriGulf | Job site | Web pages only | ❌ Excluded | Terms of use prohibit automated collection |
| Glassdoor | Job site | Web pages only | ❌ Excluded | Terms of use prohibit automated collection |
| Bayt | Job site | Web pages only | ❌ Excluded | Terms of use prohibit automated collection and derivative works |
| Jadarat | Government platform | Nafath login | ❌ Excluded | Requires Nafath (Saudi national SSO tied to a citizen's national ID) |
| Taqat | Government platform | Nafath login | ❌ Excluded | Requires Nafath |
| Qiwa | Government platform | Nafath login | ❌ Excluded | Requires Nafath |

### 2.1 Excluded sources in detail

**Terms of use (LinkedIn, Indeed, GulfTalent, NaukriGulf, Glassdoor, Bayt).** None offers a
public jobs API, and their terms prohibit automated collection. LinkedIn's `robots.txt` was checked
directly: automated access requires prior written approval. Bayt's terms also prohibit derivative
works, a stricter clause than plain anti-scraping. Indeed, GulfTalent, NaukriGulf and Glassdoor
were assessed earlier in the investigation and carry the same category of restriction.

**Nafath authentication (Jadarat, Taqat, Qiwa).** All three require login through Nafath, which is
tied to a real citizen's national ID. Unattended collection would mean using a real person's
identity, which is both technically infeasible and a clear breach of the platforms' access policy.

**Note on JSearch.** JSearch reads Google for Jobs, so some of its records were originally
published on LinkedIn, Bayt or GulfTalent. The team does not access those sites: the data is
obtained from JSearch under JSearch's own commercial terms. This distinction is recorded
deliberately.

---

## 3. The selected sources

The six sources fall into two families, and the difference drives most of the pipeline design.

| | ATS job boards | Aggregators |
|---|---|---|
| **Sources** | Ashby, Greenhouse, SmartRecruiters, Workable | Jooble, JSearch |
| **Scope of one request** | One company's whole board | One keyword and location query |
| **Completeness** | A board file lists every open job of that company | No query returns everything; coverage depends on query design |
| **Who published the job** | The employer | Other sites (job boards, other aggregators, ATS pages) |
| **Disappearance means** | The posting was taken down | Possibly only that the query did not return it |

### 3.1 What was collected

| Source | Collection scope | Collection dates (UTC) | Unique listings |
|---|---|---|---|
| Ashby | 10 company boards, filtered to Saudi locations in the script | 16, 24, 25, 27 and 28 Sep 2026 | 49 |
| Greenhouse | 17 company boards, filtered to Saudi locations in the script (and in staging for the first collection) | 9, 24, 25, 27 and 28 Sep 2026 | 219 |
| SmartRecruiters | 14 companies, Saudi postings through the API's `country=sa` filter | 19, 24, 25, 27 and 28 Sep 2026 | 952 |
| Workable | 11 company accounts, filtered to Saudi Arabia in the script | 16, 24, 25, 27 and 28 Sep 2026 | 1,549 |
| Jooble | Campaign: 23 locations, then 24 job-title keywords within Riyadh. General query on 26 Sep; campaign repeated in full on 27 Sep | 9–10, 26 and 27 Sep 2026 | 12,828 |
| JSearch | Campaign: general query, cities, Riyadh keywords, and `date_posted` windows (today / 3 days / week / month), up to 20 pages each. General query on 26 Sep; campaign repeated in full on 27–28 Sep | 10–12, 26, 27 and 28 Sep 2026 | 4,893 |
| **Total** | | | **20,490** |

The aggregator campaign was repeated in full on 27–28 September, so that week is the first with all
six sources fully pulled. Even a repeated search returns a different ranking and subset, so it
cannot show which listings were taken down. Aggregator listings therefore have no lifecycle status:
their jobs are `unknown` (`data_model.md`, section 7.1).

ATS boards were found manually (no ATS offers a list of its clients): by web search for each
platform's job-page pattern, then keeping boards that returned Saudi postings.

### 3.2 Field coverage after collection

Measured in Snowflake on the staged data (share of listings, September 2026). The probes were
based on samples of 10–100 records; where the full data differs, this
table is the reference.

| Field | Ashby | Greenhouse | SmartRecruiters | Workable | Jooble | JSearch |
|---|---|---|---|---|---|---|
| Company name | Board slug only (mapped by a seed) | ✅ | ✅ | ✅ | 21% placeholder (`Private Company`), 3% empty | 0.4% placeholder |
| City field | 78% | ❌ free-text location only | ✅ 100% | ✅ 99.9% | ❌ free-text location only | 97% |
| Employment type | ✅ | 12% | ✅ | 66% | ❌ | 99% |
| Remote / workplace | ✅ | ❌ | ✅ remote and hybrid flags | Remote flag only | ❌ | Remote flag only |
| Experience level | ❌ | ❌ | ✅ | 59% | ❌ | ❌ |
| Posting date | ✅ | ✅ | ✅ | ✅ | ❌ (`updated` is a crawl time) | Partial (missing when the posting text is Arabic) |
| Oldest posting still live | Feb 2026 | Sep 2024 | Jul 2018 | Jan 2024 | — | — |
| Description | Full | Full (HTML) | Full | Full (HTML) | Snippet (~280 characters) | Full |
| Salary | Off in our script (`includeCompensation=false`); the API can return bands | ❌ | ❌ | ❌ | `salary` field ~96% empty; no title mentions one | Mentioned in 2 titles |

Corrections to the probe results:

- **Jooble company names are less reliable than the probe suggested.** The 20-record probe found
  real company names; the full data has 21% `Private Company` placeholders.
- **Workable volume.** The probe on one account found 35 Saudi postings; eleven Saudi accounts
  gave 1,535, most of them from one recruitment agency (Eram Talent).
- **JSearch posting dates** in the campaign stop at 10 September, because the campaign ran on
  10–12 September.
- **Ashby salary.** The probe found no salary field; the API returns salary bands when called with
  `includeCompensation=true`, which our script sets to `false`.

---

## 4. How the findings shaped the pipeline

| Finding | Design decision | Where |
|---|---|---|
| No source reports whether a posting is open, filled or closed | Lifecycle is inferred from disappearance between collections, and only for ATS boards, whose files list every open job | Staging `is_active`; `lifecycle_status` in `fct_jobs` (`data_model.md`, section 7.1) |
| Workable publishes one record per target city under the same `shortcode` | Listing key is `shortcode` + city | `stg_workable_jobs` |
| Only SmartRecruiters filters by country on the server | Ashby, Greenhouse and Workable are filtered by location keywords in the extraction scripts; Greenhouse also in staging, because its first collection was not filtered (24 non-Saudi postings removed) | Extraction scripts; `stg_greenhouse_jobs` |
| Ashby returns no company name | Board slugs are mapped to company names | `seed_company_aliases` |
| Cities are written many ways (`جدة` / `Jeddah`, `RIY`, `Ad Dammām`, `Al Qassim Region`) | One lookup table maps every spelling to a standard city and region | `seed_city_mapping` (219 spellings) |
| Aggregators republish each other and the ATS boards (JSearch lists Jooble as a publisher; Jooble lists `smartrecruiters.com` and `boards.greenhouse.io`) | Cross-source matching; two listings from the same publisher are never merged | Data model Section 8 |
| Recruitment agencies appear as the employer (Eram Talent, Jobs for Humanity, Hudson Manpower) | Agencies are flagged and excluded from the top-employers question | `seed_company_aliases`; data model Q3 |
| Experience level exists only in Workable and SmartRecruiters | The experience question is answered for those sources only, and says so | Data model Q7 |
| Salary is almost never provided | Salary is out of scope | Data model Section 2 |
| Jooble caps each query at 1,000 results and allows 500 requests per key, lifetime | Queries were partitioned by location, then by title within Riyadh; a repeat Jooble collection must fit the remaining quota | `pipeline/ingestion/collection_methodology.md` |

---

## 5. Limitations

- **Coverage is not exhaustive.** ATS coverage depends on which boards were found; aggregator
  coverage depends on query design, and some Jooble keyword windows and the JSearch page cap were
  still returning results when collection stopped.
- **Aggregators were collected as one campaign** (9–12 September), plus a re-run of the general
  query only on 26 September. Their listings cannot yet show when a job was taken down; the full
  campaign is to be repeated.
- **Early probes used small samples.** Section 3.2 replaces their field estimates with measured
  values.
