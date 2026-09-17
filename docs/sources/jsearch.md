# JSearch (OpenWeb Ninja)

Owner: Shaha Yousef. Status: collected.

Both sources assigned to this workstream are **query-scoped aggregators**: every request requires a keyword and a location, and there is no "return everything" endpoint. Coverage is therefore determined entirely by query matrix design, unlike the board-scoped ATS sources handled by the rest of the team.

`GET https://api.openwebninja.com/jsearch/search` — returns **no total count at all**, so window size is unknowable and the saturation curve is the only available measure. Location and title queries both saturated almost immediately; the axis that worked was **`date_posted`** (today / 3days / week / month), which does not merely filter but **re-ranks the entire result set**, so each value opens a different window onto the same data.

---

## Method

Each source was probed before collection to establish real constraints rather than assumed ones. A **pre-flight guard** sent one request per candidate query and cancelled the pull if the result was empty or if the source had silently ignored the parameter. A **stopping rule was declared in advance**: stop expanding an axis when marginal yield (new unique records ÷ requests spent) averaged over the last five queries falls below 2.

Raw responses are stored **verbatim as strings**, one file per page, inside a batch-scoped directory, alongside the request that produced them. Nothing is transformed at ingestion and duplicates are deliberately retained in the raw layer; deduplication belongs in the curated layer, via MERGE on a deterministic business key.

See [docs/collection_methodology.md](../collection_methodology.md) for exactly how this stopping rule is (and isn't) enforced in the current code, and [docs/raw_layer.md](../raw_layer.md) for the current raw storage layout.

---

## Volumes

| Source | Rows landed | Unique records | Duplication |
|---|---|---|---|
| JSearch | 3,089 | 1,924 | 37.7% |

Business key: JSearch `job_uid` (verified stable across identical repeat requests, 10 of 10).

---

## Key findings

**1. Both sources are aggregators of aggregators.** In Jooble, `jobleads.com` alone accounts for 3,283 records (40%). In JSearch, LinkedIn (897) and Jobrapido (811) account for **89%** of all records, and Jobrapido is itself an aggregator. Provenance is therefore two or three hops from the employer in most records.

**2. JSearch republishes Jooble.** The publisher field contains `Jobs In Saudi Arabia - Jooble` (5) and `Jooble` (4). The two "independent" sources partially feed each other, which makes cross-source entity resolution mandatory rather than optional.

**3. Location data quality differs sharply between sources.** Jooble returns canonical labels. JSearch returns the same city under multiple representations — Jeddah appears as both `جدة` (215) and `Jeddah` (159); Dammam as `Ad Dammām` (209), `الدمام` (94) and `Dammam` (11); Khobar as `الخبر`, `Al Khubar` and `Al Khobar`. Riyadh also appears as the airport code `RIY` (104), and the city is missing entirely in 64 records. This is the single largest standardisation workload in the project.

---

## Source distribution

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

## Known limitations

- **Exhaustive coverage is not technically possible.** JSearch collection stopped at a self-imposed 20-page cap while pages were still returning full results, so more data remains available there.
- **Neither source exposes a posting status field**, and neither provides a reliable publication date. JSearch populates absolute dates in only 6 of 10 records without a `date_posted` filter. Posting lifecycle must therefore be derived from disappearance across repeated runs.
- Unique counts are by source identifier. **The same job posted to two platforms carries two different identifiers**, so the true count of distinct real-world vacancies is lower. Cross-source entity resolution is pending.
