<!-- dbt/data_modeling/data_model.md: the same content as the data model document (.docx) -->
# Data Model: Job Market Data Pipeline (Saudi Arabia)

*Dimensional model for the curated job-market dataset, following the dimensional modeling process: business questions → business process → grain → dimensions → measures and flags → validation.*

| **Pattern**           | Star schema: one fact table (fct_jobs, accumulating snapshot) joined to 8 dimensions, with one bridge table for the many-to-many link between jobs and skills |
|-----------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------|
| **Approach**          | ELT: raw files loaded untouched into Snowflake, transformed with dbt. The ATS files hold the Saudi postings kept at extraction (section 12)                                                                                           |
| **Dimension history** | Type 1 (overwrite). Job history is kept in the fact through six date roles: posted, first seen, last seen, opening, open until, disappeared                   |
| **Business timezone** | Asia/Riyadh. Aggregator timestamps are converted before their date is taken; an ATS pull date is the UTC date of the run (section 12)                                                                                            |
| **Status**            | Staging, intermediate and marts built and tested in Snowflake: 323 checks passed (section 11) |
| **Date**              | 2026-09-29 (data collected up to 2026-09-28) |

## 1. Analytics goals

**Goal: job market insight.** Give job seekers, career centers, and workforce analysts a view of hiring demand in Saudi Arabia: where the jobs are, who is hiring, what kind of roles are open, and which skills they ask for.

Dataset reliability is not an analytics goal. The questions about it describe the pipeline, not the market, so they do not shape the star schema. They are answered in the Data quality report (section 10), because the project guide grades explicit quality results and a stated matching strategy with its error cases.

## 2. Business questions

Each question has one measure, one dimension (or one hierarchy), and one time frame. Two time frames are used:

- **Observation period.** From the first successful pull to the latest one (as_of_date). A job belongs to the period when its open interval, from its first seen date to its open-until date, overlaps it. Every job in fct_jobs does, because it was seen at least once.

- **Reporting week, Sunday to Saturday.** Used for events that happen on a date: a new opening (opening date) or a disappearance (disappeared date). The week comes from the event's date role in dim_date.

| **\#** | **Question**                                                                                                                            | **Time frame**               | **Data availability (final build, 2026-09-28)**                                                                                    |
|--------|-----------------------------------------------------------------------------------------------------------------------------------------|------------------------------|--------------------------------------------------------------------------------------------------------------------------------|
| Q1     | How many unique job openings were open in Saudi Arabia during the observation period?                                                   | Observation period           | 19,148 jobs from 20,490 listings                                                                                               |
| Q2     | Which regions had the most open job openings during the observation period? City is the drill-down inside the same geography hierarchy. | Observation period           | 96.3% of listings at city level; 328 region-level and 424 country-level listings count at their own level only |
| Q3     | Which employers had the most open job openings during the observation period, excluding undisclosed employers and recruitment agencies? | Observation period           | Excludes the Unknown member (Employer not disclosed) and companies flagged is_recruitment_agency                               |
| Q4     | Which role families had the most open job openings during the observation period? Job category is the drill-down.                       | Observation period           | All jobs, from titles; 18.5% of jobs fall in Other                                                                          |
| Q5     | What share of open job openings during the observation period falls into each employment type?                                          | Observation period           | Jobs with a known employment type; the known share is shown with the answer                                                    |
| Q6     | Which experience levels are most requested in each region during the observation period?                                                | Observation period           | Answered from the level the source states: 1,804 jobs from Workable and SmartRecruiters, 1,794 of them with a known region. Title rules add 5,684 jobs but can return only Internship, Mid-Senior or Director, so they are kept out of this answer |
| Q7     | How many new job openings appeared in each week?                                                                                        | Week of the opening date     | Jobs with an employer-board listing only: 174 (150 in the week of 2026-09-20, 24 in the week of 2026-09-27)                         |
| Q8     | For job openings that disappeared in each week, what was the median number of days they were listed?                                    | Week of the disappeared date | Jobs with an employer-board listing only: 177 disappeared (141 and 36; median 46 and 30.5 days)                                                               |
| Q9     | Which skills are mentioned by the largest share of open job openings that have a full description, during the observation period?       | Observation period           | 5,554 of the 7,430 jobs whose posting has a full description mention at least one skill; jobs whose posting is a Jooble snippet are outside the denominator |

**Open jobs, not new openings, for composition.** Q4 to Q6 and Q9 describe the jobs open during the period. New openings are 174 employer-board jobs, too few to describe the market's composition; Q7 tracks them directly.

**Open during a chosen week.** A job is open during any period when its first seen date is on or before the period's end and its open-until date is on or after its start (section 7.3). Weekly comparisons are read against collection coverage (section 10.2), because a source not fully pulled in a week looks like a drop in the market.

*Note: three items are not business questions.*

- **Workplace type mix.** Workplace type was known for 7.9% of listings on 2026-09-24, most of them from SmartRecruiters, so the answer would describe one platform. workplace_type stays as an attribute.

- **Dataset reliability.** Answered in the Data quality report, section 10.

- **Salary.** 371 listings (1.8%) carry a salary, too few for a market question. The field is standardised where present (section 7.1).

## 3. Business process and fact table type

***Job advertisement lifecycle: an employer publishes a job advertisement, and the pipeline observes it on one or more sources across repeated pulls until it disappears.***

| **Fact type**         | **One row per**            | **Decision**                                                                                                                                                          |
|-----------------------|----------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Transaction           | Each sighting of a listing | Not chosen: answers questions about pulls, not jobs                                                                                                                   |
| Accumulating snapshot | Job, whole lifecycle       | fct_jobs. One date per milestone (posted, first seen, last seen, opening, open until, disappeared). A new pull updates the row as the job moves through its lifecycle |

Every business question is a plain join from fct_jobs to one dimension. A weekly question takes the week from the date role of its event, so the week is a dimension attribute, not a separate table.

fct_jobs is rebuilt from staging on every run, so its history is as complete as the staging history.

## 4. Grain

**fct_jobs: one row represents one unique job advertisement in one Saudi location, after cross-source matching, regardless of how many sources published it.**

**Advertisement, not headcount.** No source gives the number of vacancies, so one advertisement hiring five people is one job.

**Why the unique job and not the listing.** Counting listings would count a job published on three sources three times. The listing level is not lost: int_jobs_matched holds one row per listing with the job it was assigned to, and fct_jobs carries listing_count and source_count.

**Location.** The location is the city when it is known, otherwise the region, otherwise the country (section 6, dim_location).

**Several cities in one location text.** "Riyadh or Jeddah" is one job whose city is not fixed, so it is not split into two. The job is kept at the region the named cities share, else at country level. Measured: 5 listings. One of them, "Jeddah, Makkah, Saudi Arabia", is a city followed by its own region; it is kept at Makkah region (section 12).

**Workable multi-city postings.** Workable publishes a posting open in several cities as one object per city. Each city is one job, because the source itself separates them; the posting stays one row in dim_job_posting. Measured: 19,148 jobs from 18,693 postings.

**Expected rows.** 20,490 listings became 19,148 jobs: 17,925 jobs from one posting, 1,203 jobs merged by the exact tier and 20 by the fuzzy tier (section 8.7).

## 5. Schema overview

The model consists of one fact table, 8 dimension tables, and one bridge table:

- **FCT_JOBS:** Accumulating snapshot, one row per job. Measures (job_count, listing_count, source_count, days_listed, salary with its published text), lifecycle attributes (lifecycle_status, status_basis, is_baseline, is_censored), and foreign keys, including six date roles.

- **DIM_JOB_POSTING:** One row per posting, one to many with fct_jobs. What the posting says: job_title, description_text, description_basis, job_url, apply_url.

- **DIM_COMPANY:** Employer after entity resolution: company_sk, company_name, company_norm, industry, is_recruitment_agency.

- **DIM_LOCATION:** Geography hierarchy with a level: location_sk, city, region, country, location_level, location_label.

- **DIM_ROLE:** Two-level role hierarchy from titles: role_sk, job_category, role_family.

- **DIM_DATE:** Role-playing date dimension for the six date roles: date_sk, full_date, day_of_week, week_start_date, month, quarter, year, is_weekend.

- **DIM_JOB_ATTRIBUTES:** Junk dimension: job_attributes_sk, employment_type, workplace_type, remote_status, experience_level, experience_level_basis.

- **DIM_SOURCE:** Source of the job's representative listing: source_sk, source_name, source_type, collection_method, source_priority.

- **DIM_SKILL:** Skills and technologies: skill_sk, skill_name, skill_group. Reached through BRIDGE_JOB_SKILL.

- **BRIDGE_JOB_SKILL:** One row per job per skill.

## 6. Dimensions

Every dimension except dim_source contains an Unknown member ('-1', or -1 for dim_date), used only when nothing at all is known. dim_source needs none: every job has a representative listing, and every listing comes from a known source. A fact row whose value is missing points to it instead of carrying a null foreign key, so every relationships test holds and reports can group missing values explicitly. In dim_job_attributes, the combination where every attribute is Unknown is that member, so there is one Unknown row, not two. Every surrogate key is built with dbt_utils.generate_surrogate_key().

### dim_job_posting: what the advertisement says

One row per posting. A Workable posting open in several cities is one row here and one job per city in fct_jobs, so the relationship is one to many. Holds the long text so the fact table stays narrow. Every column is what the posting itself says, so it depends on posting_sk alone; a value that can come from another listing merged into the job, such as the salary, stays in fct_jobs.

| **Column**          | **Type**    | **Description**                                                                         |
|---------------------|-------------|-----------------------------------------------------------------------------------------|
| posting_sk          | STRING (PK) | Hash of source_name + source_job_id; a Workable posting keeps one key across its cities |
| job_title           | STRING      | Title from the representative listing                                                   |
| description_text    | STRING      | Cleaned description of the posting (the job's representative listing)                 |
| description_basis   | STRING      | full; snippet when the posting is a Jooble snippet; none when it has no description    |
| job_url / apply_url | STRING      | From the representative listing                                                         |

### dim_role: what role

| **Column**   | **Type**    | **Description**                                                                                                                                                                                                              |
|--------------|-------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| role_sk      | STRING (PK) | Hash of job_category                                                                                                                                                                                                         |
| job_category | STRING      | From title keywords (seed_job_categories, 171 keywords, 18 categories): the most specific keyword wins (lowest priority number), then the longest. Other when no keyword matches; Unknown when the title has no matching key |
| role_family  | STRING      | From seed_role_families; every category belongs to exactly one family                                                                                                                                                        |

The hierarchy has two levels by design, so the dimension is never a single attribute. The families come from seed_role_families; a job with no title key points to the Unknown member.

| **role_family**              | **job_category**                                                                                 |
|------------------------------|--------------------------------------------------------------------------------------------------|
| Technology and Data          | IT & Software; Data & Analytics                                                                  |
| Engineering and Construction | Engineering; Construction & Trades                                                               |
| Business and Finance         | Management; Consulting & Strategy; Finance & Accounting; Legal; Administration; HR & Recruitment |
| Sales, Marketing and Service | Sales & Business Development; Marketing; Customer Service; Design & Creative                     |
| Operations and Hospitality   | Operations & Supply Chain; Hospitality & Food                                                    |
| Health and Education         | Healthcare; Education & Training                                                                 |
| Other                        | Other                                                                                            |

### dim_company: who is hiring

| **Column**            | **Type**    | **Description**                                                                                                                 |
|-----------------------|-------------|---------------------------------------------------------------------------------------------------------------------------------|
| company_sk            | STRING (PK) | Hash of company_norm; '-1' is Employer not disclosed                                                                            |
| company_name          | STRING      | Standard name from seed_company_aliases, else the name on the company's highest-priority listing                                |
| company_norm          | STRING      | Matching key: the standard name, normalised                                                                                     |
| industry              | STRING      | Most frequent industry across the company's listings (Workable and SmartRecruiters only); ties go to the higher-priority source |
| is_recruitment_agency | BOOLEAN     | From seed_company_aliases; true for agencies and platforms that post for other employers                                        |

**Employer entity resolution.** Exact matching on a cleaned name is not enough, so resolution runs in three steps:

1\. **Normalise.** Lower-case, punctuation removed, legal suffixes and labels removed (company, co, ltd, limited, inc, llc, plc, corp, group, est, careers, jobs, ksa, saudi arabia, شركة, مؤسسة). Placeholders such as Private Company and Confidential map to the Unknown member.

2\. **Alias seed.** seed_company_aliases maps 742 spellings to one standard name each; 195 of them are flagged as recruitment agencies.

3\. **Candidates.** analyses/companies_not_in_seed lists pairs of company keys in the same city where one key contains the other as whole words ("qiddiya" in "qiddiya investment") or they share most of their words. A team member accepts or rejects each pair; accepted pairs go into the seed.

**Result on the final build.** The seed maps 742 spellings to 545 employers and the Unknown member. 12,753 listings carry a spelling from the seed, and 253 company keys gather more than one spelling (564 spellings, 6,696 listings). The candidates analysis still lists 295 pairs, 284 of them where one name contains the other; they were not reviewed after 2026-09-24, so some employers may still appear under two keys (section 12).

Measured examples the process must catch (2026-09-24): Qiddiya Investment Company (364 listings) and Qiddiya (58); JASARA PMC (203) and Jasara Program Management Company (39); WSP (56) and WSP Global Inc. (33); AtkinsRéalis (178) and its former name SNC-Lavalin (53). Brands stay as advertised: SOFITEL, RAFFLES, and FAIRMONT are not merged into AccorHotel.

### dim_location: where

| **Column**     | **Type**    | **Description**                                                                         |
|----------------|-------------|-----------------------------------------------------------------------------------------|
| location_sk    | STRING (PK) | Hash of city + region + location_level                                                  |
| city           | STRING      | Standard city from seed_city_mapping; Unknown below city level                          |
| region         | STRING      | Standard region (13 Saudi regions); Unknown at country level                            |
| country        | STRING      | 'SA'                                                                                    |
| location_level | STRING      | city, region, or country                                                                |
| location_label | STRING      | Display name: the city, "\<region\> (no city given)", or "Saudi Arabia (no city given)" |

The city is looked up in the city field first, then in the location text. A match inside a longer match is part of it ("makkah" in "makkah province"). Measured on 2026-09-28: 19,738 listings at city level, 328 at region level (for example Jooble's "Al Qassim Region"), 424 at country level. No listing carries a non-Saudi country in its location fields; section 12 describes the Jooble jobs based abroad that arrive under a Saudi location.

### dim_date: when

| **Column**             | **Type** | **Description**                                                |
|------------------------|----------|----------------------------------------------------------------|
| date_sk                | INT (PK) | YYYYMMDD                                                       |
| full_date              | DATE     | Calendar date in Asia/Riyadh                                   |
| day_of_week            | STRING   | Day name                                                       |
| week_start_date        | DATE     | Sunday that starts the week; the key for every weekly question |
| month / quarter / year | INT      | Calendar attributes                                            |
| is_weekend             | BOOLEAN  | Friday and Saturday (Saudi weekend)                            |

fct_jobs joins dim_date in six roles: posted, first seen, last seen, opening, open until, and disappeared. The range runs from the earliest date of any role to the latest successful pull, so every role has a row: posting dates reach back to 2018-07-11, and open_until_date can reach the latest pull. Aggregator envelopes carry the collection time, which is converted to Asia/Riyadh before the date is taken. An ATS file carries only the ingest_date of its folder, which the extraction scripts wrote as the UTC date of the run, and that calendar date is used as it is. A pull made between 00:00 and 03:00 Riyadh time therefore carries the day before; on the final data this can move only one pull to the previous week, and not one that Q7 or Q8 count (section 12).

### dim_source: where the representative listing was collected

| **Column**        | **Type**    | **Description**                                                              |
|-------------------|-------------|------------------------------------------------------------------------------|
| source_sk         | STRING (PK) | Hash of source_name                                                          |
| source_name       | STRING      | workable, smartrecruiters, ashby, greenhouse, jsearch, jooble                |
| source_type       | STRING      | ATS (employer job boards) or Aggregator (query-based search engines)         |
| collection_method | STRING      | Company board API or Query matrix API                                        |
| source_priority   | INT         | 1 to 6, in the order above; decides the representative listing (section 8.6) |

fct_jobs references it through primary_source_sk, the source of the job's representative listing. The job's other sources are counted in listing_count per source and source_count.

### dim_job_attributes: what kind of job (junk dimension)

| **Column**             | **Type**    | **Values**                                                                                                |
|------------------------|-------------|-----------------------------------------------------------------------------------------------------------|
| job_attributes_sk      | STRING (PK) | Hash of the five attributes                                                                               |
| employment_type        | STRING      | Full-time, Part-time, Contract, Internship, Temporary, Volunteer, Full-time and Part-time, Other, Unknown |
| workplace_type         | STRING      | Remote, Hybrid, OnSite, Unknown                                                                           |
| remote_status          | STRING      | Remote, Not remote, Unknown                                                                               |
| experience_level       | STRING      | Internship, Entry, Associate, Mid-Senior, Director, Executive, Unknown                                    |
| experience_level_basis | STRING      | source, title, unknown                                                                                    |

**Source values.** Experience level is a closed vocabulary taken from the values Workable and SmartRecruiters use (seed_experience_levels). The mapping ignores letter case. Counts measured on 2026-09-24:

| **Source value (Workable, SmartRecruiters)** | **Listings** | **Standard value**        |
|----------------------------------------------|--------------|---------------------------|
| Internship                                   | 25           | Internship                |
| Entry level                                  | 527          | Entry                     |
| Associate                                    | 201          | Associate                 |
| Mid-Senior level                             | 851          | Mid-Senior                |
| Director                                     | 118          | Director                  |
| Executive                                    | 70           | Executive                 |
| Not Applicable                               | 50           | Title rules, else Unknown |
| Empty (Workable)                             | 636          | Title rules, else Unknown |
| No field (other four sources)                | 10,450       | Title rules, else Unknown |

**Title rules.** When the source gives no level, a word in the title decides it (seed_seniority_keywords). A word is kept when the 1,510 postings whose source gives a level agree with it at least 70% of the time:

| **Title word**              | **Level**                     | **Labelled postings** | **Agreement** |
|-----------------------------|-------------------------------|-----------------------|---------------|
| director                    | Director                      | 119                   | 72%           |
| intern, interns, internship | Internship                    | 7                     | 100%          |
| senior                      | Mid-Senior                    | 185                   | 74%           |
| lead                        | Mid-Senior                    | 37                    | 73%           |
| leader                      | Mid-Senior                    | 11                    | 82%           |
| manager                     | Mid-Senior                    | 295                   | 81%           |
| assistant manager           | None: blocks the manager rule | 11                    | 45%           |

Left out: junior (40%), trainee (44%), consultant (64%). Together the rules agree with the source 78% of the time (measured on the 26 September export). On the final build the level is known for 39.1% of jobs, 9.4% from the source field alone. Precedence: source field, then title rule, then Unknown; experience_level_basis records which.

The rules can return Internship, Mid-Senior or Director only, never Entry, Associate or Executive, because no title word reached 70% agreement for those levels. A comparison of levels across regions therefore uses the source field alone (Q6). A hand check of 20 title-based levels on 2026-09-29 found 18 reasonable; the two doubtful ones were "Site Lead Assistant" (Mid-Senior from lead) and "General Manager (Bakery & Retail)" (Mid-Senior from manager).

### dim_skill: which skills

| **Column**  | **Type**    | **Description**                                                                        |
|-------------|-------------|----------------------------------------------------------------------------------------|
| skill_sk    | STRING (PK) | Hash of skill_name                                                                     |
| skill_name  | STRING      | Canonical skill from seed_skills                                                       |
| skill_group | STRING      | One of 12 groups, for example Data and AI, Cloud and DevOps, Certifications, Languages |

seed_skills holds 133 keywords for 125 skills: terms found in at least 10 of the 4,304 postings with a full description. Ambiguous words are left out: sales, kpi, hospitality, tax, lean, soc, iam, swift, react, vulnerability, .net, c#.

## 7. Facts, measures and bridge

### 7.1 fct_jobs

Built from int_job_openings, which applies the survivorship and lifecycle rules once, so every column below has one definition.

| **Column**                                          | **Kind**               | **Logic**                                                                                                                       |
|-----------------------------------------------------|------------------------|---------------------------------------------------------------------------------------------------------------------------------|
| job_sk                                              | PK                     | From int_jobs_matched (section 8.5)                                                                                             |
| posting_sk                                          | FK                     | dim_job_posting; the representative listing's posting                                                                           |
| company_sk, location_sk, role_sk, job_attributes_sk | FK                     | Survivorship rules, section 8.6; '-1' when nothing is known                                                                     |
| primary_source_sk                                   | FK                     | dim_source; the representative listing's source                                                                                 |
| posting_date_sk                                     | FK (role: posted)      | Earliest employer-board posting date, else the earliest of any listing; -1 when none                                            |
| first_seen_date_sk                                  | FK (role: first seen)  | First seen date across the job's listings                                                                                       |
| last_seen_date_sk                                   | FK (role: last seen)   | Last seen date across the job's listings                                                                                        |
| opening_date_sk                                     | FK (role: opening)     | First seen date of a new opening (rules below); -1 otherwise                                                                    |
| open_until_date_sk                                  | FK (role: open until)  | Last day the job counts as open (rules below)                                                                                   |
| disappeared_date_sk                                 | FK (role: disappeared) | Disappeared date of a disappeared job; -1 otherwise                                                                             |
| lifecycle_status                                    | Attribute              | open, disappeared, or unknown (rules below)                                                                                     |
| status_basis                                        | Attribute              | employer board when the job has an ATS listing; aggregator query otherwise                                                      |
| is_baseline                                         | Flag                   | True when any of the job's listings was seen in the baseline pull of its board or source                                        |
| is_censored                                         | Flag                   | True when the job has not disappeared, so its duration is not complete                                                          |
| match_tier                                          | Attribute              | single, exact (two or more postings in one exact group), or fuzzy                                                              |
| job_count                                           | Measure, additive      | 1 per row                                                                                                                       |
| listing_count                                       | Measure, additive      | Listings merged into the job; also one column per source (listing_count_workable and the others)                                |
| copies_landed                                       | Measure, additive      | Landed copies of those listings in RAW                                                                                          |
| source_count                                        | Measure, non-additive  | Distinct sources among the job's listings                                                                                       |
| days_listed                                         | Measure, non-additive  | Disappeared jobs only: days from the posting date (else first seen) to the disappeared date. Summarised by median, never summed |
| days_listed_basis                                   | Attribute              | posted or first_seen                                                                                                            |
| salary_text                                         | Attribute              | Salary as published, from the listing the parsed salary fields come from                                                        |
| salary_min_amount, salary_max_amount                | Measure, non-additive  | Parsed from the salary text as published                                                                                        |
| salary_currency                                     | Attribute              | SAR or USD                                                                                                                      |
| salary_period                                       | Attribute              | hour, day, week, month, or year                                                                                                 |
| salary_min_sar_month, salary_max_sar_month          | Measure, non-additive  | Converted for month, week and year; null for hour and day                                                                       |

**Pull calendar.** int_landed_files reads the file metadata in RAW, the only intermediate model that does, because staging flattens files into postings and a failed pull leaves no trace there. A pull is successful when its payload is a job list: for an ATS board, a jobs array, an empty one included, and not an error body; for an aggregator page, HTTP 200 with a parseable body. int_board_pulls holds one row per board, or per aggregator source, per pull date. Without this rule, one failed request would mark every job on that board as disappeared.

**Baseline pull.** The first successful pull of each ATS board, and the first collection week of each aggregator. Every job it contains existed before the pipeline looked, so none of them is a new opening. At first sight the median posting was already 137 days old in SmartRecruiters and 94 days in Workable, and Jooble has no posting date.

**Full pull per week.** int_source_weeks records, for each source and week, whether the source was fully pulled: for an ATS source, a successful pull of every board that existed by the end of the week and ever held a posting (Ashby camunda, pulled once with no posting, is not required); for an aggregator, a week that repeats the baseline campaign's queries (aggregator_campaign_coverage, 1.0 means all of them).

**Lifecycle status.** No source exposes a posting status, so a closed posting and a removed posting cannot be told apart; both are recorded as disappeared.

- An ATS listing disappears when staging marks it inactive and K successful pulls of its own board confirm it is gone (disappearance_misses = 1). A failed pull confirms nothing. K = 1 is enough: none of the 2,769 ATS listings was missing from a successful pull of its board and then seen again, so a second confirming pull would change no status.

- A job is disappeared when every one of its ATS listings disappeared, and open while one is still on its board.

- A job found on aggregators only is unknown. A query result is a ranked slice of the market, so a listing missing from a later run may still be open.

**What disappeared means.** The listing left its board's public list and stayed off it in every later pull. On 2026-09-29, 11 disappeared listings were opened in a browser: 9 were closed (6 of 6 from Greenhouse, 3 of 5 from SmartRecruiters). The other 2, both AccorHotel postings, were missing from four consecutive pulls of the company's Saudi list (about 300 postings each) while their pages still accepted applications. The pipeline recorded what the board published; an employer can keep a page open after taking it off its list.

**The disappeared date is the first pull that confirmed the absence**, not the day the posting closed. Greenhouse was pulled on 2026-09-09 and next on 2026-09-24, so 45 of its 50 disappeared listings carry 24 September although the posting may have closed on any day in between. The same gap explains why Greenhouse has the highest share of disappeared listings: its postings were observed for 19 days, against 9 to 12 days for Workable, SmartRecruiters and Ashby, whose first pulls were on 16 and 19 September.

**Open interval.** The job counts as open from its first seen date to its open-until date:

- Disappeared job: the day before its disappeared date.

- Any other job: its latest evidence plus the recent window (recent_window_days = 7, the weekly collection schedule), never later than the latest successful pull. The latest evidence of an ATS listing still on its board is its board's latest successful pull; of an aggregator listing, its last seen date.

**New openings.** A job is a new opening when it has an employer-board listing and none of its listings was seen in a baseline pull; its opening date is its first seen date. A job found on aggregators only never gets an opening date: first appearing in a later campaign is no more evidence of a new opening than disappearing is of a closure. On the final build, 6,931 jobs were outside the baseline; 6,757 of them were aggregator-only, and 174 are new openings.

**Salary.** Parsed from the salary text when it follows one grammar: currency, amount or range, period ("SAR 15000 - 17000 per month", "\$45000 per year"). Every one of the 371 salary texts on 2026-09-28 follows it. The amount is first turned into a yearly amount (month x12, week x52, year x1), converted at 3.75 SAR per USD from seed_currency_rates, and divided by 12 at the end, so no precision is lost before rounding (\$45,000 a year gives 14,063 SAR a month). Hourly and daily amounts are not converted, because the hours and days worked per month are unknown. Amounts are kept as the source published them; section 12 lists implausible source values. Salary text inside titles is not parsed. The salary text sits in fct_jobs next to the parsed fields, because it can come from an aggregator copy of the job rather than from its representative posting.

### 7.2 bridge_job_skill

Grain: one row per job per skill. Built from int_job_skills (22,822 rows on the final build). A skill keyword is matched as a whole word in the titles and cleaned descriptions of every listing of the job, not only the representative.

| **Column** | **Kind**  | **Logic**                                           |
|------------|-----------|-----------------------------------------------------|
| job_sk     | FK        | fct_jobs                                            |
| skill_sk   | FK        | dim_skill                                           |
| matched_in | Attribute | title, when found in a title; description otherwise |

### 7.3 Answering by time frame

| **Time frame**              | **How**                                                                                          | **Questions**                  |
|-----------------------------|--------------------------------------------------------------------------------------------------|--------------------------------|
| Observation period          | Every row of fct_jobs                                                                            | Q1 to Q6, Q9                   |
| Week of an event            | opening_date_sk or disappeared_date_sk joined to dim_date, grouped by week_start_date            | Q7, Q8                         |
| Open during a chosen period | Filter: first seen date on or before the period's end, and open-until date on or after its start | Any follow-up by week or month |

### 7.4 Using the model in Power BI

- Relationships: every dimension 1:\* fct_jobs, filtering from the dimension to the fact. dim_date is loaded once and related through each date role; only one role is active at a time, the others are used with USERELATIONSHIP.

- Skills: dim_skill 1:\* bridge_job_skill \*:1 fct_jobs. The bridge to fct_jobs relationship filters in both directions, so a skill filter reaches the jobs.

- A job with three skills appears three times in the bridge, so jobs are counted as a distinct count of job_sk whenever the bridge is in the filter path.

- Postings are counted as a distinct count of posting_sk, because a Workable posting in several cities is several jobs.

## 8. Cross-source matching specification

Assigns one job_sk to every listing of the same real job, in three models: int_listing_groups (exact tier), int_match_candidates (fuzzy candidate pairs), and int_jobs_matched (fuzzy tier and job keys). Sources share no common identifier, so matching is heuristic, and every rule is designed to be explainable and measurable.

### 8.1 Publisher rule

**Two postings that one publisher lists on one source are never merged.** The publisher is the employer's own board for an ATS listing, and the site the listing came through for an aggregator listing (Jooble's source domain, JSearch's job_publisher), normalised so "Jobrapido" and "Jobrapido.com" are one publisher.

If Workable lists two postings with the same title and city under different IDs, the employer itself says they are two openings. Inside one match key, each publisher's postings on each source are ranked by posting date, first seen, and posting key, and paired rank to rank: the first posting of every publisher forms one group, the second the next one. So an employer's two identical-looking postings stay two jobs, and each can still take an aggregator copy.

**Why the source is part of the rule.** One publisher reached through two aggregators is one posting seen twice, not two postings. The first version ranked by publisher alone, so a JobLeads posting returned by both JSearch and Jooble was ranked 1 and 2 and kept as two jobs: 49 match keys on 2026-09-28, and in all 49 the Jooble snippet is part of the JSearch description. Ranking per publisher and source merges them.

**Why publisher, not source.** An aggregator republishes many sites, so two Jooble listings from different publishers can be the same job. Measured on 2026-09-24 (same lower-cased title, company, and place, different IDs):

| **Source**         | **Groups** | **Listings in groups** | **Share of source** | **Groups across different publishers** |
|--------------------|------------|------------------------|---------------------|----------------------------------------|
| Jooble             | 216        | 594                    | 7.2%                | 19                                     |
| JSearch            | 11         | 22                     | 1.1%                | 6                                      |
| Workable (control) | 38         | 84                     | 5.5%                | Not applicable                         |

A rule by source would leave the 25 cross-publisher groups unmerged; the publisher rule merges them. Workable shows the base rate of employers posting the same title twice in one city.

### 8.2 Matching keys (built in int_job_listings)

| **Key**      | **Rules**                                                                                                                                                                                                                                     | **Example**                                                                          |
|--------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------|
| title_norm   | Lower-case; Unicode dashes, quotes and Arabic punctuation removed and "&" read as "and"; bracketed notes and punctuation removed (a title made only of a bracketed note keeps the text inside: "(Accountant)" → "accountant"); sr, jr, mgr expanded to senior, junior, manager; hiring noise (urgent, hiring, required, saudi nationals) and location words (ksa, saudi arabia, riyadh, jeddah, dammam, khobar) removed | "Senior Oil & Gas Safety Officer (Saudi National)" → "senior oil and gas safety officer" |
| company_norm | Employer entity resolution, section 6 (dim_company); null for undisclosed employers                                                                                                                                                           | "Qiddiya Investment Company" and "Qiddiya" → one key once the alias is in the seed   |
| city_std     | seed_city_mapping on the city field, else on the location text; null when the text names several cities                                                                                                                                       | جدة, Jiddah → Jeddah; "Riyadh or Jeddah" → no city                                   |

### 8.3 Blocking

Candidates are compared only inside a block of the same company_norm and the same city_std. Comparing all 20,490 listings pairwise would mean about 210 million pairs. A listing with no company, no city (region or country level only), or no title key is never matched and stays a job of its own.

### 8.4 Matching tiers

1\. **Exact tier (int_listing_groups):** listings with the same title_norm, company_norm and city_std form one group, under the publisher rule.

2\. **Fuzzy candidates (int_match_candidates):** pairs of exact groups inside one block whose titles differ, that share no publisher on one source, and whose titles carry the same level words (intern, internship, trainee, apprentice, assistant, associate, junior, senior, lead, head, principal, manager, director, chief, deputy, vice, demi, ii, iii, iv; 2, 3 and 4 count as ii, iii and iv). Both scores are stored: Jaccard on title words and Jaro-Winkler, 0 to 100. Pairs where both scores are below 50 are dropped to keep the table small.

3\. **Fuzzy tier (int_jobs_matched):** a candidate pair is merged when the chosen score reaches the threshold and each group is the other's best candidate; ties go to the higher score, then the closer first seen dates, then the group key.

A best match is one to one, so groups are joined in pairs and a chain of matches cannot form. Together with the no-shared-publisher condition, two postings of one publisher on one source never end in one job by construction; tests check it and that a fuzzy job joins exactly two groups.

The score and its threshold were chosen from labelled pairs (section 8.7): Jaccard at 80. A test build showed why labels are needed: Jaro-Winkler scored different Qiddiya jobs that share the prefix "Assistant Manager -" at 86 to 93 ("Assets Infrastructure Delivery" and "Asset Infrastructure Design": 93), while their Jaccard score stayed at 43 or below.

**Punctuation the title key must remove.** [[:punct:]] in Snowflake covers ASCII only. JSearch writes a Unicode dash where Jooble writes a hyphen, and "and" where the employer board writes "&", so the same title stayed two exact groups: long titles still reached the fuzzy threshold, and a three-word title with a dash scored 75 and stayed two jobs. Most of the 57 fuzzy merges measured after the publisher fix differed only this way. The title key now removes that punctuation, so these copies merge in the exact tier. About 800 titles of the final build carry a Unicode dash.

### 8.5 Job key

job_sk is the source_record_sk of the earliest-seen listing in the job; ties go to the lower source_record_sk. Later listings do not move the key, so labelled samples and stored references keep pointing to the same job across runs.

### 8.6 Survivorship

One listing represents the job, chosen by source_priority, then first seen, then source_record_sk: Workable → SmartRecruiters → Ashby → Greenhouse → JSearch → Jooble. Each field then follows its own rule, applied once in int_job_openings:

| **Field**                                                         | **Rule**                                                                          |
|-------------------------------------------------------------------|-----------------------------------------------------------------------------------|
| posting, source, company, location, job_category, job_title, URLs, description_text, description_basis | Representative listing |
| employment_type                                                   | First known value by priority                                                     |
| experience_level                                                  | A level from the source field before one from a title rule, then priority         |
| workplace_type and remote_status                                  | Taken as a pair from the first listing, by priority, whose remote status is known |
| Salary (text and every parsed field)                              | Taken together from the first listing, by priority, that has a salary text; stored in fct_jobs |
| posting_date                                                      | Earliest employer-board posting date, else the earliest of any listing            |
| first seen, last seen                                             | Minimum and maximum across listings                                               |
| lifecycle                                                         | Section 7.1                                                                       |
| industry (dim_company)                                            | Most frequent value; ties go to the higher-priority source                        |

### 8.7 Evaluation and threshold

The threshold was chosen from labelled pairs, and every merge it produced was then checked.

1\. **Sample.** analyses/fuzzy_review_sample drew up to 10 candidate pairs from every 10-point band of each score, from 50 to 100.

2\. **Labels.** 88 pairs were labelled in seeds/seed_match_review.csv (listing_a, listing_b, is_same_job, reviewer). A pair is the same job when both listings advertise one opening: same employer, same city, same role and level. The listing that stands for each group is chosen with a unique tie-break, so the labels join on every build.

3\. **Threshold.** analyses/match_threshold_evaluation gives precision and in-sample recall for every threshold, for both scores. The threshold was chosen on the build of 2026-09-28, when 84 of the 88 labelled pairs were candidates:

| **Score and threshold** | **Precision** | **In-sample recall** |
|---|---|---|
| Jaccard 75 | 0.65 (13 of 20) | 0.684 (13 of 19) |
| **Jaccard 80 (chosen)** | **0.917 (11 of 12; 95% interval 0.65 to 0.99)** | **0.579 (11 of 19)** |
| Jaccard 85 | 1.0 (3 of 3) | 0.158 (3 of 19) |
| Jaro-Winkler, best threshold (95) | 0.80 or lower | 0.42 |

After the review fixes of 2026-09-29 (publisher rule per source, punctuation in the title key, grade numbers as level words), 76 of the 88 labelled pairs are still candidates, 14 of them the same job. Pairs whose titles now match exactly left the candidates, so the pairs left are the harder ones. analyses/match_label_status shows where each labelled pair stands: of the other 12, 4 same-job pairs now merge in the exact tier (their titles differed only by a dash), 7 different-job pairs are no longer compared, and 1 same-job pair is no longer compared because "4 months" in one title is read as a grade (it scored 70 before, below the threshold, so no merge changed). No pair labelled as two jobs was merged. On the 76:

| **Score and threshold** | **Precision** | **In-sample recall** |
|---|---|---|
| Jaccard 75 | 0.538 (7 of 13) | 0.5 (7 of 14) |
| **Jaccard 80 (kept)** | **0.833 (5 of 6; 95% interval 0.44 to 0.97)** | **0.357 (5 of 14)** |
| Jaccard 85 | 1.0 (1 of 1) | 0.071 (1 of 14) |
| Jaro-Winkler, best threshold (95) | 0.667 (4 of 6) or lower | 0.286 (4 of 14) |

Jaccard at 80 is still the point where precision is high and recall has not collapsed. Jaro-Winkler rewards shared prefixes ("Assistant Manager -"), so it merges different jobs of one employer. In-sample recall is measured on a sample drawn by score band, so it describes the sample, not every pair.

4\. **Audit of every merge.** analyses/fuzzy_merge_audit lists every job the fuzzy tier formed, with the titles of all its listings. Each audit changed a rule:

- The first audit found "Demi Chef de Partie" merged with "Chef de Partie"; demi, ii, iii and iv were added to the level words.
- The audit of the 51 merges of 2026-09-28 found 49 the same job and two errors: Qiddiya "IT Security Design" with "IT Security", and GE Vernova "Commissioning Specialist-2" with "Commissioning Specialist". 2, 3 and 4 were added as grades.
- After the publisher fix the tier made 57 merges, most of them titles that differ only by a Unicode dash or "&". The title key now removes that punctuation (section 8.4), so they merge in the exact tier.

In the final build the fuzzy tier makes 20 merges. Read by title on 2026-09-29, 18 are the same job, 1 is a different job and 1 is uncertain, so precision is 0.90 (18 of 20; 95% interval 0.70 to 0.97), or 0.95 if the uncertain merge is the same job:

- Different job: Qiddiya, "Senior Specialist - IT Security Design" merged with "Senior Specialist - IT Security".
- Uncertain: KBR, "Principal Structural Design Engineer" merged with the same title followed by "- Offshore".

**Result on the final build:** 20,490 listings; 17,925 jobs from one posting; 1,203 jobs merged by the exact tier; 20 merged by the fuzzy tier; 27,207 scored candidate pairs.

## 9. Tests

The rules below have a dbt test, so a run that breaks one fails instead of producing wrong numbers.

| **Test**                                  | **Applies to** |
|-------------------------------------------|----------------|
| unique, not_null                          | Every primary key: job_sk, posting_sk, every dimension key; source_record_sk in every intermediate model at listing grain |
| unique_combination_of_columns (dbt_utils) | job_sk + skill_sk in bridge_job_skill; posting_sk + location_sk in fct_jobs; source_name + board + pull_date in int_board_pulls; source_name + week_start_date in int_source_weeks; the two groups of a candidate pair |
| relationships                             | Every foreign key of fct_jobs and bridge_job_skill to its dimension, including each date role |
| accepted_values                           | lifecycle_status, status_basis, location_level, employment_type, workplace_type, remote_status, experience_level, experience_level_basis, salary_currency, salary_period, description_basis, match_tier, matched_in |
| has_one_unknown_member (custom)           | Every dimension except dim_source has exactly one Unknown member |
| Every listing kept (custom)               | Listings equal the six staging models; matching keeps every listing; fct_jobs reconciles with the listings |
| Publisher rule (custom)                   | No job holds two postings of one publisher on one source |
| Job survivorship (custom)                 | One employer and one location per job; job_sk is the job's earliest listing; the representative listing has the job's best source priority; a fuzzy job joins exactly two exact groups and any other job one |
| One representative per job (custom)       | Exactly one representative listing in every job |
| Fuzzy merges keep level words (custom)    | No fuzzy merge joins titles with different level words |
| Lifecycle consistency (custom)            | A job is open on its first day; disappeared_date is set exactly when the job disappeared, and after its last sighting on an employer board; a baseline or aggregator-only job has no opening date and every other job has one; no job is open after the latest successful pull |
| Location and salary (custom)              | A text naming several cities gets no city; salary amounts are positive, the minimum is not above the maximum, a monthly SAR value exists exactly when the period converts, and it equals the amount made yearly, converted with seed_currency_rates and divided by 12 |
| RAW to staging (custom)                   | RAW reconciles with staging; the latest successful pull of each ATS board holds at least half the postings of its pull before (boards with 10 or more postings), so a collapsed board fails the build |

**Rules checked by analyses and hand checks, not by tests.** The precision of the fuzzy threshold (labelled pairs and the audit of every merge, section 8.7); the city-before-region and containment rules of the location lookup (intermediate_checks counts region-level listings that name one city: 0); the definition of a full pull per week (int_source_weeks, section 10.2); employer entity resolution (companies_not_in_seed, section 6).

**Results of the final build.** 10 seeds, 25 models and 288 data tests: 323 passed, 0 warnings, 0 errors (2026-09-29). Idempotency: two consecutive builds on the same data gave identical hash_agg fingerprints and row counts for int_job_listings, int_jobs_matched, int_match_candidates, int_job_openings, int_job_skills, int_board_pulls, fct_jobs and bridge_job_skill. This was checked before the review fixes of 2026-09-29; the fixes also order the aggregator copy that staging keeps down to the file and the position in the page.

## 10. Data quality report

The reliability questions become this report. It is produced on every build by the tests in section 9 and three analyses: intermediate_checks (the intermediate layer), pipeline_audit (RAW to staging), and model_checks (the marts).

| **\#** | **Measure**                                                                                             | **Produced by**                                 |
|--------|---------------------------------------------------------------------------------------------------------|-------------------------------------------------|
| DQ1    | Listings collected, per source                                                                          | pipeline_audit                                  |
| DQ2    | Records removed from RAW to staging, with the reason                                                    | pipeline_audit                                  |
| DQ3    | Unique jobs after cross-source matching, by match tier                                                  | intermediate_checks                             |
| DQ4    | Share of jobs published on more than one source                                                         | model_checks                                    |
| DQ5    | Fuzzy candidate pairs, and matching precision in the labelled sample                                    | intermediate_checks, match_threshold_evaluation |
| DQ6    | Share of listings each standardisation resolved (location level, experience level basis, salary parsed) | intermediate_checks                             |
| DQ7    | Pulls that failed, and sources fully pulled in each week                                                | intermediate_checks                             |
| DQ8    | Jobs by lifecycle status; baseline jobs and new openings                                                | intermediate_checks                             |
| DQ9    | Skill coverage among jobs with a full description                                                       | intermediate_checks                             |
| DQ10   | Company spellings not yet in the alias seed                                                             | companies_not_in_seed                           |

### 10.1 Results of the final build (data up to 2026-09-28, built 2026-09-29)

| **Check**                                                | **Value**                | **Expected**                             |
|----------------------------------------------------------|--------------------------|------------------------------------------|
| Listings = sum of the six staging models                 | 20,490                   | 20,490                                   |
| Jobs: single / exact / fuzzy                             | 17,925 / 1,203 / 20      | fuzzy = the merges in fuzzy_merge_audit  |
| Job postings (dim_job_posting, without Unknown)          | 18,693                   | Fewer than jobs (Workable multi-city)    |
| Jobs on 1 / 2 / 3 sources                                | 18,140 / 972 / 36        | Cross-source overlap is a lower bound    |
| Same publisher through JSearch and Jooble left as two jobs | 0                      | 0                                        |
| Fuzzy candidate pairs                                    | 27,207                   | Scored pairs; a sample is labelled       |
| Listings at city / region / country level                | 19,738 / 328 / 424       | City for most                            |
| Listings naming several cities                           | 5                        | A handful                                |
| Listings kept at region level although one city is named | 0                        | 0                                        |
| Jobs by experience level basis: source / title / unknown | 1,804 / 5,684 / 11,660   | Title adds coverage                      |
| Salary texts / parsed                                    | 371 / 371                | Equal                                    |
| Jobs by lifecycle: open / disappeared / unknown          | 2,584 / 177 / 16,387     | unknown = aggregator-only                |
| Baseline jobs / not in baseline                          | 12,217 / 6,931           | Not in baseline only after a second pull |
| New openings (employer-board jobs with an opening date)  | 174                      | Aggregator-only jobs never counted       |
| ATS listings inactive in staging but not disappeared     | 0                        | 0 with K = 1 and no failed pull          |
| ATS board pulls that failed                              | 0                        | Each one explained                       |
| Jobs with a skill, among jobs whose posting has a full description | 5,554 of 7,430 | Coverage for Q9                          |
| bridge_job_skill rows = int_job_skills rows              | 22,822 = 22,822          | Equal                                    |
| Postings shared by several jobs with a different description per job | 0 of 214     | 0                                        |
| dbt build                                                | 323 passed               | 0 warnings, 0 errors                     |

Row counts of the ten exported tables are listed in 02_code/01_data/final_datasets/README.md.

### 10.2 Collection coverage by week

| **Week starting** | **Fully pulled** | **Sources**                                                                                                        |
|-------------------|------------------|--------------------------------------------------------------------------------------------------------------------|
| 2026-09-06        | 3 of 3 pulled    | jooble, jsearch, greenhouse                                                                                        |
| 2026-09-13        | 3 of 3 pulled    | smartrecruiters, workable, ashby                                                                                   |
| 2026-09-20        | 4 of 6           | smartrecruiters, ashby, greenhouse, workable; the aggregators were pulled but did not repeat the baseline campaign |
| 2026-09-27        | 6 of 6           | all six: every baseline query of Jooble and JSearch was repeated on 27 and 28 September, and every ATS board that ever held a posting was pulled |

"Fully pulled" counts the sources collected that week; in the first two weeks the other three sources were not collected at all. An ATS week is full when every board that existed by the end of the week and ever held a posting was pulled: Ashby camunda, pulled once on 2026-09-24 with no posting, was not pulled in the week of 2026-09-27 and is not required. The week of 2026-09-27 is the first with all six sources fully pulled. It was collected on 27 and 28 September, so its weekly counts (Q7, Q8) cover two days, not a full week.

### 10.3 Field completeness baseline, measured 2026-09-24

| **Source**      | **Listings** | **No usable company** | **City field empty** | **Employment type empty** | **Workplace type empty** | **Median description (chars)** |
|-----------------|--------------|-----------------------|----------------------|---------------------------|--------------------------|--------------------------------|
| Jooble          | 8,262        | 23.5%                 | 100% (no field)      | 100%                      | 100%                     | 279                            |
| JSearch         | 1,924        | 0.4%                  | 3.4%                 | 0.7%                      | 98.4%                    | 2,261                          |
| Workable        | 1,535        | 0.0%                  | 0.1%                 | 34.5%                     | 99.6%                    | 2,514                          |
| SmartRecruiters | 943          | 0.0%                  | 0.0%                 | 0.0%                      | 0.0%                     | 1,337                          |
| Greenhouse      | 215          | 0.0%                  | 100% (no field)      | 88.4%                     | 100%                     | 9,987 (escaped HTML)           |
| Ashby           | 49           | 0.0%                  | 22.4%                | 0.0%                      | 8.2%                     | 4,500                          |

### 10.4 Pipeline audit: RAW to staging

analyses/pipeline_audit, final build of 2026-09-28. The test assert_raw_reconciles_with_staging passes.

| **Source**      | **Landed files** | **Failed pages** | **RAW rows** | **Out of scope** | **Within-source duplicates** | **Staged listings** |
|-----------------|-----------------:|-----------------:|-------------:|-----------------:|-----------------------------:|--------------------:|
| Jooble          | 1,753            | 0                | 32,297       | 0                | 19,469                       | 12,828              |
| JSearch         | 993              | 101              | 7,624        | 0                | 2,731                        | 4,893               |
| Workable        | 55               | n/a              | 7,378        | 0                | 5,829                        | 1,549               |
| SmartRecruiters | 70               | n/a              | 4,544        | 0                | 3,592                        | 952                 |
| Greenhouse      | 85               | n/a              | 867          | 24               | 624                          | 219                 |
| Ashby           | 51               | n/a              | 227          | 5                | 173                          | 49                  |
| **Total**       | **3,007**        | **101**          | **52,937**   | **29**           | **32,418**                   | **20,490**          |

Within-source duplicates are the same posting landed more than once: in every ATS snapshot while it stays open, and in overlapping aggregator queries and date windows. Out of scope are non-Saudi postings (24 in the unfiltered Greenhouse files of 2026-09-09; 5 Ashby postings matched by a keyword such as "hail" in "Thailand"). JSearch's 101 failed pages are pages that returned HTTP 429, 403 or 504 when a key's quota ran out or the gateway timed out; they are landed on purpose, carry no rows, and were re-requested under a new batch. An employer board is pulled as one file per board, not in pages, so the column does not apply to it (n/a).

### 10.5 Hand checks on the final build (2026-09-29)

Tests prove that rules hold; they cannot prove that a rule gives the right answer. These checks compare the output with the real postings.

| **Check** | **Sample** | **Result** |
|---|---|---|
| Fuzzy merges (section 8.7) | All 20, read by title | 18 the same job; 1 different job and 1 uncertain, both named |
| Fuzzy threshold (section 8.7) | 76 labelled pairs still candidates | Jaccard 80: precision 0.833, in-sample recall 0.357 |
| One publisher through JSearch and Jooble (section 8.1) | All 49 match keys | The Jooble snippet is part of the JSearch description in 49 of 49; merged |
| Disappeared listings opened in a browser (section 7.1) | 11, across Greenhouse and SmartRecruiters | 9 closed; 2 AccorHotel postings off the board's list but still open |
| Experience level from title rules (section 6) | 20 | 18 reasonable, 2 doubtful |
| Salary parsing and conversion (section 7.1) | 10, then every value above 60,000 SAR a month or paid by the hour or day | Parsing correct; a rounding loss in the conversion was found and fixed; implausible source values listed in section 12 |
| Texts naming several cities (section 4) | All 5 | 4 name two cities; 1 is a city followed by its region |
| Repeated build | 8 tables | Identical fingerprints (before the review fixes) |

## 11. Build status

| **Object** | **Status on 2026-09-29** |
|---|---|
| stg\_\* (6) | Built, tests passing |
| int_landed_files, int_board_pulls, int_source_weeks | Built, tests passing |
| int_job_listings, int_listing_groups, int_match_candidates, int_jobs_matched, int_job_openings, int_job_skills | Built, tests passing |
| Seeds (10) | Built: sources, city mapping, company aliases, job categories, role families, experience levels, seniority keywords, skills, currency rates, match review |
| fct_jobs, dim_job_posting, dim_company, dim_location, dim_role, dim_job_attributes, dim_date, dim_source, dim_skill, bridge_job_skill | Built, tests passing (323 checks); exported to ADLS curated/ as Parquet and to final_datasets/ as CSV after this build |

## 12. Known limitations

Each limitation is stated with its measured size, so a user outside the team knows where the dataset is thin. Figures are from the final build (data up to 2026-09-28) unless another date is given.

| **Limitation**                               | **Size**                                                                                                        | **Effect**                                                                                                |
|----------------------------------------------|-----------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------------------|
| One week with every source fully pulled       | Only the week of 2026-09-27, collected on 27 and 28 September; earlier weeks miss one to three sources | Week-to-week changes before 2026-09-27 can be changes in collection; weekly answers are read against section 10.2 |
| Lifecycle known for employer-board jobs only | 2,761 of 19,148 jobs (14.4%); 16,387 aggregator-only jobs are unknown | Q7 and Q8 describe employer-board jobs |
| Few new openings                             | 174, all from employer boards; 6,757 aggregator-only jobs outside the baseline are not counted | Q7 has two weekly points, the second covering two days |
| Closed and removed postings look the same    | 2 of 11 disappeared listings checked in a browser were off their board's list but still open | Disappeared means removed from the public list, which was a closing in 9 of 11 checks |
| Disappeared date is a pull date              | 45 of 50 disappeared Greenhouse listings dated 24 September, after a 15-day gap between pulls | The date is an upper bound, so days_listed runs long, most for Greenhouse; Q8 uses the median |
| ATS pull dates are UTC dates                 | The extraction scripts named each ATS folder with the UTC date of the run. Late-night collection was common: 626 of 1,753 Jooble pages and 170 of 993 JSearch pages were collected between 00:00 and 03:00 Riyadh time. ATS pulls are dated 9, 16, 19, 24, 25, 27 and 28 September | A pull made before 03:00 Riyadh time carries the day before. Only a Saturday date can move a pull to the wrong week: the SmartRecruiters baseline pull of 19 September, which gives no opening or disappearance, so Q7 and Q8 are unchanged; days_listed can be one day long. Collection has ended, so the dates are documented, not rewritten |
| RAW holds the Saudi scope of the ATS boards   | The Workable, Ashby and Greenhouse scripts kept only Saudi-located postings before saving (Greenhouse from 24 September; its 9 September files are unfiltered), and the Workable script also dropped postings without a title or a link. SmartRecruiters files are the Saudi postings of its API (country=sa), each with its jobAd added from a detail request | Non-Saudi postings cannot be re-examined from RAW. Staging re-checks the scope on the structured country field or the location text (pipeline/README.md, collection_methodology.md) |
| Old postings on ATS boards                   | Posting dates back to 2018-07-11 | The posting date does not define new openings; Q8 uses the median |
| Undisclosed employers and agencies           | 13.6% of jobs have no disclosed employer; Private Company alone was 13.4% of listings on 2026-09-24; 195 aliases flag recruitment agencies | Never matched across sources when undisclosed; both excluded from employer questions |
| Employer candidates not reviewed             | 295 candidate pairs in companies_not_in_seed, 284 where one name contains the other | Some employers may appear under two keys in dim_company, which splits them in Q3 |
| Location less precise than city              | 328 region-level and 424 country-level listings; 41 Jooble listings say only "Remote"; "Jeddah, Makkah, Saudi Arabia" (1 listing) is kept at Makkah region | Not matched with city-level listings; country-level jobs are shown on their own row in Q2, not under a region |
| Workable multi-city postings                 | 19,148 jobs from 18,693 postings | A flexible opening advertised in several cities counts once per city |
| Sparse attributes                            | Experience level known for 39.1% of jobs (9.4% from the source alone); employment type known for 35.2% of jobs; on 2026-09-24 workplace type 7.9% of listings | Attribute questions describe the covered subset; coverage is shown with each answer |
| Title rules for experience level             | Agree with the source field 78% of the time; return Internship, Mid-Senior or Director only | Title-based levels carry basis = title and are left out of Q6 |
| Stated experience level from two platforms   | 1,804 jobs, all from Workable and SmartRecruiters | Q6 describes the employers on those two platforms, not the whole market |
| Short Jooble descriptions                    | Median 279 characters on 2026-09-24, against 1,337 to 4,500 elsewhere | Skill shares use jobs whose posting has a full description only |
| Salary                                       | 371 listings (1.8%); hourly and daily amounts not converted; implausible Jooble values kept as published: SAR 500,000 to 700,000 per month ("Sr. Sales Engineer"), SAR 170,000 to 470,000 per month ("Roustabout"), \$75,000 per hour ("Purchase Executive") | Stored where present; no salary question |
| Jooble jobs based abroad                     | Jooble can return a posting based outside Saudi Arabia under a Saudi search location, for example "General Dermatologist - Multiple Locations, Ohio" | Not detectable from the location fields; the count is not measured |
| Fuzzy matching errors                        | 1 of 20 fuzzy merges is a different job and 1 is uncertain; in-sample recall 0.357 on the labelled pairs still candidates | Some jobs worded differently on two sources stay two jobs, so the unique job count is slightly high |
| Exact tier on generic titles                 | Not measured; for example "Saudi Engineer" at one recruitment agency in one city | Two openings with the same generic title, employer and city on two publishers become one job |

## 13. Parameters and how they were set

Each parameter is a dbt variable or a seed, so it can be changed without editing a model. Every value below was set from a measurement or, where marked, from a stated policy.

| **Parameter** | **Value** | **Set by** |
|---|---|---|
| Fuzzy score and threshold (fuzzy_match_function, fuzzy_match_threshold) | Jaccard, 80 | 84 labelled pairs on 2026-09-28: precision 0.917, in-sample recall 0.579; on the 76 still candidates after the review fixes: precision 0.833, recall 0.357; every merge audited (section 8.7) |
| Pulls that must miss a listing before it disappears (disappearance_misses, K) | 1 | None of the 2,769 ATS listings was missing from a successful pull of its board and then seen again |
| Days a job stays open after its last evidence (recent_window_days) | 7 | The weekly collection schedule |
| Share of the baseline queries an aggregator week must repeat (aggregator_campaign_coverage) | 1.0 | The definition of a full campaign; reached in the week of 2026-09-27 |
| Collapsed board pull (ats_collapse_ratio, ats_collapse_min_postings) | 0.5 of the pull before, boards with 10 or more postings | Policy: a board that loses more than half its postings between two pulls is treated as a broken pull. No board of the final build fell below it |
| Company aliases (seed_company_aliases) | 742 spellings, 545 employers, 195 spellings flagged as recruitment agencies | Review of analyses/companies_not_in_seed |
| Title made only of a bracketed note | Keep the text inside the brackets | "(Accountant)" was the only listing without a title key |
| Punctuation in the title key | Unicode dashes, quotes and Arabic punctuation removed; "&" read as "and" | 57 fuzzy merges after the publisher fix, most differing only this way |
| Grade numbers | 2, 3 and 4 count as the level words ii, iii and iv | The audit of 2026-09-28: "Commissioning Specialist-2" merged with "Commissioning Specialist" |

## Appendix A. Design decisions

Basis: \[GUIDE\] required by the project guide; \[WCD\] the WeCloudData capstone breakdown; \[DATA\] decided by a measurement; \[PRACTICE\] standard practice; \[TEAM\] a team decision.

| **\#** | **Decision**                                                                                                                        | **Reason**                                                                                      | **Basis**          |
|--------|-----------------------------------------------------------------------------------------------------------------------------------|-------------------------------------------------------------------------------------------------|--------------------|
| C1     | Star schema with one fact table, fct_jobs; weeks come from date roles, not from a weekly table                                | Every question is a plain join from fct_jobs to one dimension; event weeks come from date roles | \[TEAM\]           |
| C2     | Q1 to Q6 and Q9 over the observation period; Q7 and Q8 by week                                                                    | Only one week has every source fully pulled (section 10.2)                                        | \[DATA\]           |
| C3     | Q4 to Q6 and Q9 describe open jobs, not new openings                                                                              | New openings are 174 employer-board jobs, too few to describe composition                | \[DATA\]           |
| C4     | New openings only for jobs with an employer-board listing                                                                         | 6,757 of the 6,931 jobs outside the baseline were aggregator-only                                   | \[DATA\]           |
| C5     | lifecycle_status is open, disappeared, or unknown; aggregator-only jobs are unknown                                               | A listing missing from a query result proves nothing                                            | \[PRACTICE\]       |
| C6     | Pull success read from RAW file metadata: a job-list payload                                                                      | Staging keeps no trace of a failed pull                                                         | \[PRACTICE\]       |
| C7     | Disappearance needs staging's inactive flag and K successful pulls of the listing's own board                                     | A failed or skipped pull would otherwise close a whole board                                    | \[PRACTICE\]       |
| C8     | Full pull recorded per source and week; an aggregator week must repeat the baseline campaign                                      | Period comparisons are read against collection coverage                                         | \[DATA\]           |
| C9     | A text naming several cities is kept at the region they share, else country                                                       | Keeps region answers for two cities of one region                                               | \[DATA\]           |
| C10    | Publisher rule per source, not a same-source rule, with rank-to-rank pairing | 25 cross-publisher groups inside the aggregators were left unmerged; one publisher reached through two aggregators is one posting (49 keys, section 8.1) | \[DATA\] |
| C11    | Fuzzy tier: level words, mutual best match, both scores stored; Jaccard at 80 from 88 labelled pairs; every merge audited | Jaro-Winkler scored different Qiddiya jobs 86 to 93; Jaccard 80: precision 0.917 when chosen, 0.833 on the harder pairs left after the review fixes; 18 of 20 final merges the same job | \[GUIDE\] \[DATA\] |
| C12    | A unique tie-break wherever one listing is chosen                                                                                 | Labels keyed by listing must join on every build; verified with hash_agg                        | \[PRACTICE\]       |
| C13    | Experience level from title rules kept at 70% agreement or more | 78% agreement; level known for 39.1% of jobs, 9.4% from the source field alone | \[DATA\] |
| C14    | experience_level, experience_level_basis and remote_status in dim_job_attributes                                | Column names follow the code                                                                    | \[PRACTICE\]       |
| C15    | dim_job_posting at posting grain, one to many with fct_jobs                                                                       | A Workable posting in several cities is one posting and one job per city                        | \[DATA\]           |
| C16    | Role families for dim_role from seed_role_families                                                                                | Job titles must be normalised into role families                                                | \[GUIDE\]          |
| C17    | Skill dictionary decided: 133 keywords, 125 skills, 12 groups                                                                     | Terms found in at least 10 of 4,304 full descriptions                                           | \[GUIDE\] \[DATA\] |
| C18    | Salary periods week and day added; week converted, day not                                                                        | All 371 salary texts follow one grammar                                                         | \[DATA\]           |
| C19    | No listing bridge in the marts; listing provenance stays in int_jobs_matched, and fct_jobs keeps primary_source_sk and listing counts | One row per listing already exists in the intermediate layer                                    | \[PRACTICE\]       |
| C20    | Quality results produced by tests and analyses on every build, not stored in quality marts                                      | The checks read the built layers directly                                                       | \[PRACTICE\]       |
| C21    | dim_date covers every date role up to the latest successful pull                                                                  | open_until_date can fall after the last sighting                                                | \[PRACTICE\]       |
| C22    | Idempotency checked by comparing hash_agg fingerprints of two builds                                                              | The pipeline must re-run cleanly                                                                | \[GUIDE\] \[WCD\]  |
| C23    | K = 1 successful pull confirms a disappearance                                                                                    | None of the 2,769 ATS listings reappeared after missing a pull of its board                     | \[DATA\]           |
| C24    | Q6 answered from the level stated by the source only                                                                              | Title rules cannot return Entry, Associate or Executive                                          | \[DATA\]           |
| C25    | Salary kept as published; converted through a yearly amount, divided by 12 at the end                                             | Dividing first lost precision (14,062 instead of 14,063)                                        | \[DATA\]           |
| C26    | A title made only of a bracketed note keeps the text inside                                                                       | "(Accountant)" had no title key and could not be matched                                        | \[DATA\]           |
| C27    | "City, region" address texts are not special-cased                                                                                | 1 listing; a rule reading "Makkah" after "Jeddah" as a region would misread a real two-city text such as "Jeddah / Makkah" | \[DATA\] |
| C28    | Hand checks against the real postings on the final build (section 10.5)                                                           | Tests prove that rules hold, not that they give the right answer                                | \[PRACTICE\]       |
| C29    | dim_job_posting holds only what the posting says; the salary text sits in fct_jobs with the parsed fields | A job-level value stored under a posting showed one city's text for every city of a Workable posting (36 postings) | \[PRACTICE\] \[DATA\] |
| C30    | Unicode dashes, quotes, Arabic punctuation and "&" removed from the title key, not from the company key | [[:punct:]] covers ASCII only; the company aliases are stored in the old company-key form | \[DATA\] |
| C31    | Grade numbers 2, 3 and 4 are level words | "Commissioning Specialist-2" merged with "Commissioning Specialist" | \[DATA\] |
| C32    | An ATS week is a full pull only when every board that ever held a posting was pulled | One board pulled used to be enough | \[PRACTICE\] |
| C33    | The collapsed-pull check runs per board | One large board losing its list did not move a source total below half | \[PRACTICE\] |
| C34    | ATS pull dates and the Saudi filter at extraction are documented, not changed | Collection has ended; changing the scripts would describe a collection that did not produce the data | \[TEAM\] |
