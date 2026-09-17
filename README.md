# DE - 26 - A - Job Data Pipeline - Cohort 1

A data engineering capstone: a job market data pipeline for Saudi Arabia, covering all sectors and role types. Postings are collected from job aggregator APIs and ATS (applicant tracking system) job boards, landed raw, and will be cleaned, modelled and combined into one curated dataset.

---

## Sources

| Source | Type | Owner | Status |
|---|---|---|---|
| Jooble | Job aggregator | Shaha Yousef | Collected |
| JSearch (OpenWeb Ninja) | Job aggregator | Shaha Yousef | Collected |
| Greenhouse | ATS | | In progress |
| Lever | ATS | | In progress |
| Ashby | ATS | | In progress |
| Workable | ATS | | In progress |
| SmartRecruiters | ATS | | In progress |
| Recruitee | ATS | | In progress |

Each source has its own methodology doc under `docs/sources/`: what it returns, how it was probed, what limits it, and what it found. See [docs/sources/jooble.md](docs/sources/jooble.md) and [docs/sources/jsearch.md](docs/sources/jsearch.md) for the two collected so far.

---

## Volumes so far

| Source | Unique records |
|---|---|
| Jooble | 8,262 |
| JSearch | 1,924 |

Per-source breakdowns (rows landed, duplication rate, business keys, findings) are in each source's doc, not here.

---

## Repository layout

```
pipeline/
  common/          shared config, raw writer, state, query log
  ingestion/
    jooble/          collector.py + matrix.py
    jsearch/         collector.py + matrix.py
  transformation/    (placeholder, not started)
  quality/           (placeholder, not started)
probes/
  jooble/            one-off probe scripts
  jsearch/           one-off probe scripts
data_samples/
  jooble/            sample records + a raw envelope example
  jsearch/           sample records + a raw envelope example
docs/
  raw_layer.md          raw storage format, shared across all sources
  collection_methodology.md   how and why the collectors and matrices behave the way they do
  sources/
    jooble.md            Jooble method, findings, limitations
    jsearch.md            JSearch method, findings, limitations
```

Everything is organised by source: a teammate adding Greenhouse, Lever, or any other source adds `pipeline/ingestion/<source>/`, `probes/<source>/`, `data_samples/<source>/` and `docs/sources/<source>.md`, without touching anyone else's folders. Shared logic used by more than one source belongs in `pipeline/common/`.

---

## How to run

1. Copy `.env.example` to `.env` in the repo root and fill in real API keys:

   ```
   JOOBLE_API_KEYS=...
   JSEARCH_API_KEYS=...
   ```

2. Install dependencies:

   ```
   pip install -r requirements.txt
   ```

3. Run a matrix layer from the repo root:

   ```
   python pipeline/ingestion/jooble/matrix.py <l1|l1b|l1c|l1d|l2|l2b>
   python pipeline/ingestion/jsearch/matrix.py <coverage|kw|temporal>
   ```

   Each layer argument runs one query batch (or a fixed group of them) against the collector; see `docs/sources/jooble.md` and `docs/sources/jsearch.md` for what each layer targets.

---

## Docs

- [docs/collection_methodology.md](docs/collection_methodology.md): how and why each collector and matrix behaves the way it does.
- [docs/raw_layer.md](docs/raw_layer.md): the partitioned raw storage format, the envelope schema, and how resume works.
- [docs/sources/jooble.md](docs/sources/jooble.md), [docs/sources/jsearch.md](docs/sources/jsearch.md): per-source method, findings and known limitations.
