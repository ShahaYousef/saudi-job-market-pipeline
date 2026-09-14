# DE - 26 - A - Job Data Pipeline - Cohort 1

Data engineering capstone. Scope: Saudi Arabia, all sectors and role types.

This repository contains **samples only**. It is shared for review of data shape, source coverage and collection methodology.

---

## Sources

Both sources assigned to this workstream are **query-scoped aggregators**: every request requires a keyword and a location, and there is no "return everything" endpoint. Coverage is therefore determined entirely by query matrix design, unlike the board-scoped ATS sources handled by the rest of the team.

### Jooble

`POST https://sa.jooble.org/api/{key}` — returns a `totalCount` but enforces a **hard ceiling of 1000 records per query** (20 rows × 50 pages; page 51 is empty). Because the ceiling applies per query rather than per account, the market was partitioned into separate query windows: first by **location** (23 locations), then by **job title within Riyadh** (24 keywords) to break through Riyadh's own truncated window.

### JSearch (OpenWeb Ninja)

`GET https://api.openwebninja.com/jsearch/search` — returns **no total count at all**, so window size is unknowable and the saturation curve is the only available measure. Location and title queries both saturated almost immediately; the axis that worked was **`date_posted`** (today / 3days / week / month), which does not merely filter but **re-ranks the entire result set**, so each value opens a different window onto the same data.

---

## Method

Each source was probed before collection to establish real constraints rather than assumed ones. A **pre-flight guard** sent one request per candidate query and cancelled the pull if the result was empty or if the source had silently ignored the parameter. A **stopping rule was declared in advance**: stop expanding an axis when marginal yield (new unique records ÷ requests spent) averaged over the last five queries falls below 2.

Raw responses are stored **verbatim as strings**, one file per page, inside a batch-scoped directory, alongside the request that produced them. Nothing is transformed at ingestion and duplicates are deliberately retained in the raw layer; deduplication belongs in the curated layer, via MERGE on a deterministic business key.

---

## Volumes

| Source | Rows landed | Unique records | Duplication |
|---|---|---|---|
| Jooble | 14,010 | 8,262 | 41.0% |
| JSearch | 3,089 | 1,924 | 37.7% |
| **Combined** | **17,099** | **10,186** | **40.4%** |

Business keys: Jooble `id`, JSearch `job_uid` (verified stable across identical repeat requests, 10 of 10).

---

## Key findings

**1. Riyadh dominates the market.** 4,266 of 8,262 Jooble records, or **52%**. The unfiltered country-level query returned effectively a Riyadh result set; its first 31 pages were near-entirely redundant with the dedicated Riyadh pull.

**2. Peripheral regions are near-absent.** Ha'il 7 records, Najran 2, Arar 1, Unaizah 1. Digitally advertised hiring in Saudi Arabia is heavily concentrated in Riyadh, the Eastern Province and Jeddah.

**3. Both sources are aggregators of aggregators.** In Jooble, `jobleads.com` alone accounts for 3,283 records (40%). In JSearch, LinkedIn (897) and Jobrapido (811) account for **89%** of all records, and Jobrapido is itself an aggregator. Provenance is therefore two or three hops from the employer in most records.

**4. JSearch republishes Jooble.** The publisher field contains `Jobs In Saudi Arabia - Jooble` (5) and `Jooble` (4). The two "independent" sources partially feed each other, which makes cross-source entity resolution mandatory rather than optional.

**5. Minimal overlap with the team's ATS sources.** Records originating from Greenhouse (88), Recruitee (269), SmartRecruiters (209) and Lever (27) total roughly **7%** of the Jooble corpus. The remaining 93% comes from platforms outside the team's coverage — TeamTailor, Manatal, JazzHR, Breezy, TalentLyft, Recruiterflow and others.

**6. Location data quality differs sharply between sources.** Jooble returns canonical labels. JSearch returns the same city under multiple representations — Jeddah appears as both `جدة` (215) and `Jeddah` (159); Dammam as `Ad Dammām` (209), `الدمام` (94) and `Dammam` (11); Khobar as `الخبر`, `Al Khubar` and `Al Khobar`. Riyadh also appears as the airport code `RIY` (104), and the city is missing entirely in 64 records. This is the single largest standardisation workload in the project.

---

## Source distribution

### Jooble by location (top 20)

| Location | Records |
|---|---|
| Riyadh | 4,266 |
| Jeddah | 762 |
| Dammam | 564 |
| Jubail | 547 |
| Khobar | 484 |
| Mecca | 293 |
| Medina | 286 |
| Al Dhahran | 253 |
| Al Qassim Region | 159 |
| Umluj | 138 |
| Yanbu | 121 |
| Jizan | 102 |
| Tabuk | 45 |
| Abha | 39 |
| Ta'if | 33 |
| Rabigh | 32 |
| Al Ahsa | 28 |
| Saudi Arabia | 26 |
| Al Ula | 13 |
| Al Kharj | 10 |

### Jooble by originating platform (top 20)

| Platform | Records |
|---|---|
| jobleads.com | 3,283 |
| jobscoin.com | 1,789 |
| energyjobsearch.com | 569 |
| teamtailor.com | 506 |
| recruitee.com | 269 |
| manatal.com | 220 |
| smartrecruiters.com | 209 |
| accor.com | 170 |
| talentlyft.com | 133 |
| zoho.com | 116 |
| marriott.com | 101 |
| boards.greenhouse.io | 88 |
| gulfhirepoint.com | 88 |
| jazzhr.com | 53 |
| breezy.hr | 51 |
| baesystems.com | 45 |
| jooble | 37 |
| recruiterflow.com | 35 |
| ebr.consulting | 30 |
| jobs.lever.co | 27 |

### JSearch by city (top 20)

Shown unstandardised, as returned by the source.

| City | Records |
|---|---|
| Riyadh | 819 |
| جدة | 215 |
| Ad Dammām | 209 |
| Jeddah | 159 |
| RIY | 104 |
| الدمام | 94 |
| *(missing)* | 64 |
| al-'Aqrabiyyah | 28 |
| الخبر | 27 |
| Al Khubar | 21 |
| Al-Hufūf | 18 |
| Al Jubayl | 13 |
| المدينة | 12 |
| Dammam | 11 |
| al-Jubayl | 11 |
| الفيصلية | 11 |
| Madinah | 10 |
| Al Khobar | 9 |
| MAK | 8 |
| Makkah | 8 |

### JSearch by publisher (top 20)

| Publisher | Records |
|---|---|
| LinkedIn | 897 |
| Jobrapido | 811 |
| Bayt | 39 |
| BeBee | 28 |
| JobLeads | 18 |
| Jobrapido.com | 13 |
| GetSaudiJobs | 9 |
| وظف دوت نت | 9 |
| GulfTalent | 6 |
| Foundit | 6 |
| Bayt.com | 6 |
| Jobs In Saudi Arabia - Jooble | 5 |
| Workable Jobs | 4 |
| Jooble | 4 |
| إنديد | 4 |
| CareerBuilder | 4 |
| وظف دوت كوم | 3 |
| Learn4Good | 3 |
| Monster | 3 |
| Jobaaj | 2 |

---

## Repository contents

```
samples/
  jooble_sample_200.csv               200 unique records, selected fields
  jsearch_sample_200.csv              200 unique records, selected fields
  jooble_raw_envelope_example.json    one raw landed page, unmodified
  jsearch_raw_envelope_example.json   one raw landed page, unmodified
```

The envelope examples show the raw layer format: the server response stored as an unmodified string, wrapped with `source_id`, `batch_id`, `ingested_at`, `http_status` and the exact request that produced it.

---

## Known limitations

- **Exhaustive coverage is not technically possible** on either source. Jooble caps at 1,000 records per query; three keyword windows remain truncated. JSearch collection stopped at a self-imposed 20-page cap while pages were still returning full results, so more data remains available there.
- **Jooble does not support Arabic keyword search.** Arabic-language postings exist in its index (roughly 2.5% of the corpus) but cannot be targeted; they arrive incidentally.
- **Neither source exposes a posting status field**, and neither provides a reliable publication date. Jooble's `updated` is a crawl timestamp; JSearch populates absolute dates in only 6 of 10 records without a `date_posted` filter. Posting lifecycle must therefore be derived from disappearance across repeated runs.
- Salary is empty in roughly 96% of Jooble records; company name is empty in roughly 11%.
- Unique counts are by source identifier. **The same job posted to two platforms carries two different identifiers**, so the true count of distinct real-world vacancies is lower. Cross-source entity resolution is pending.
