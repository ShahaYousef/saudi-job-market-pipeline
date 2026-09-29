-- dbt/models/intermediate/int_job_openings.sql
--
-- Grain: one row per job (job_sk): one job advertisement in one Saudi location, after matching.
-- Applies the survivorship rules of data_model.md, section 8.6, once, so every mart reads
-- the same values, and the lifecycle of section 7.1.
--
--   From the representative listing   posting_sk, source, company, location, job_category,
--                                     title, URLs, description_text and description_basis: what
--                                     the posting itself says, so dim_job_posting holds values
--                                     of the posting and not of another listing merged into the job
--   First known value by priority     employment_type, salary (text and parsed fields together)
--   Source field before title         experience_level: a level the source gives beats one read
--                                     from the title, then source priority
--   Taken as a pair                   workplace_type and remote_status, from the first listing
--                                     (by priority) whose remote_status is known
--   ATS first                         posting_date: earliest ATS date, else earliest of any
--   Across all listings               first_seen / last_seen, listing counts, copies_landed,
--                                     source_count
--
-- Lifecycle (section 7.1). No source reports a posting's status, so only disappearance from an
-- employer board is evidence; closed and removed postings cannot be told apart.
--   lifecycle_status   'disappeared' when every ATS listing of the job disappeared (K misses,
--                      int_job_listings); 'open' when an ATS listing is still on its board;
--                      'unknown' for a job found on aggregators only (a query result is a ranked
--                      slice, so a missing listing proves nothing).
--   open_until_date    last day the job counts as open: the day before it disappeared, else its
--                      latest evidence plus var('recent_window_days'), never after the latest
--                      successful pull. A job is open during a period when
--                      first_seen_date <= period end and open_until_date >= period start.
--   opening_date       first_seen_date, only for jobs with an employer-board listing that were
--                      not seen in any baseline pull: those are new openings. A baseline job
--                      existed before the pipeline looked. A job found on aggregators only has no
--                      opening date: a query result is a ranked slice, so a job missing from an
--                      earlier campaign may simply not have been returned (the same reason its
--                      disappearance proves nothing).
--
-- status_basis: 'employer board' when the job has an ATS listing, else 'aggregator query'.
-- is_active is computed from employer-board evidence only (null for aggregator-only jobs) and is
-- not passed on to the marts: lifecycle_status carries that rule.
--
-- "Priority" = source_priority from seed_sources, then first seen, then source_record_sk.

with listings as (
    select
        *,
        row_number() over (
            partition by job_sk
            order by source_priority, first_seen_at, source_record_sk
        ) as priority_rank
    from {{ ref('int_jobs_matched') }}
),

as_of as (
    select max(pull_date) as as_of_date
    from {{ ref('int_board_pulls') }}
    where is_successful
),

representative as (
    select * from listings where is_representative
),

aggregated as (
    select
        job_sk,

        coalesce(min_by(employment_type,  iff(employment_type  <> 'Unknown', priority_rank, null)), 'Unknown')
                                                                                  as employment_type,
        coalesce(min_by(experience_level, iff(experience_level <> 'Unknown',
                                              iff(experience_level_basis = 'source', 0, 1000000) + priority_rank, null)), 'Unknown')
                                                                                  as experience_level,
        coalesce(min_by(experience_level_basis, iff(experience_level <> 'Unknown',
                                              iff(experience_level_basis = 'source', 0, 1000000) + priority_rank, null)), 'unknown')
                                                                                  as experience_level_basis,
        coalesce(min_by(workplace_type,   iff(remote_status    <> 'Unknown', priority_rank, null)), 'Unknown')
                                                                                  as workplace_type,
        coalesce(min_by(remote_status,    iff(remote_status    <> 'Unknown', priority_rank, null)), 'Unknown')
                                                                                  as remote_status,

        -- salary: every field from the same listing, the first by priority that has a salary text
        min_by(salary_text,          iff(salary_text is not null, priority_rank, null)) as salary_text,
        min_by(salary_is_parsed,     iff(salary_text is not null, priority_rank, null)) as salary_is_parsed,
        min_by(salary_currency,      iff(salary_text is not null, priority_rank, null)) as salary_currency,
        min_by(salary_period,        iff(salary_text is not null, priority_rank, null)) as salary_period,
        min_by(salary_min_amount,    iff(salary_text is not null, priority_rank, null)) as salary_min_amount,
        min_by(salary_max_amount,    iff(salary_text is not null, priority_rank, null)) as salary_max_amount,
        min_by(salary_min_sar_month, iff(salary_text is not null, priority_rank, null)) as salary_min_sar_month,
        min_by(salary_max_sar_month, iff(salary_text is not null, priority_rank, null)) as salary_max_sar_month,

        coalesce(min(iff(source_type = 'ATS', posting_date, null)), min(posting_date))
                                                                                  as posting_date,
        min(first_seen_at)                                                        as first_seen_at,
        max(last_seen_at)                                                         as last_seen_at,
        min(first_seen_date)                                                      as first_seen_date,
        max(last_seen_date)                                                       as last_seen_date,
        -- last sighting on an employer board: disappearance is decided from the boards, and an
        -- aggregator copy can outlive the employer's own posting
        max(iff(source_type = 'ATS', last_seen_date, null))                       as ats_last_seen_date,

        -- employer-board evidence only
        -- boolor_agg ignores nulls and returns null when every value is null
        boolor_agg(iff(source_type = 'ATS', is_active, null))                     as is_active,
        iff(count_if(source_type = 'ATS') > 0, 'employer board', 'aggregator query')
                                                                                  as status_basis,

        -- lifecycle inputs (data_model.md, section 7.1)
        boolor_agg(is_baseline)                                                   as is_baseline,
        count_if(source_type = 'ATS')                                             as ats_listings,
        count_if(source_type = 'ATS' and is_disappeared)                          as ats_listings_disappeared,
        max(iff(source_type = 'ATS', disappeared_date, null))                     as last_disappeared_date,
        max(last_evidence_date)                                                   as last_evidence_date,

        -- matching
        case
            when count_if(match_tier = 'fuzzy') > 0 then 'fuzzy'
            when count(distinct posting_sk) > 1      then 'exact'
            else 'single'
        end                                                                       as match_tier,
        max(fuzzy_match_score)                                                    as fuzzy_match_score,

        count(*)                                                                  as listing_count,
        count_if(source_name = 'workable')                                        as listing_count_workable,
        count_if(source_name = 'smartrecruiters')                                 as listing_count_smartrecruiters,
        count_if(source_name = 'ashby')                                           as listing_count_ashby,
        count_if(source_name = 'greenhouse')                                      as listing_count_greenhouse,
        count_if(source_name = 'jsearch')                                         as listing_count_jsearch,
        count_if(source_name = 'jooble')                                          as listing_count_jooble,
        sum(copies_landed)                                                        as copies_landed,
        count(distinct source_name)                                               as source_count
    from listings
    group by job_sk
),

lifecycle as (
    select
        a.*,
        case
            when a.ats_listings = 0                              then 'unknown'
            when a.ats_listings_disappeared = a.ats_listings     then 'disappeared'
            else 'open'
        end                                                                       as lifecycle_status
    from aggregated a
)

select
    a.job_sk,
    r.posting_sk,
    r.source_name                                         as primary_source_name,
    r.source_type                                         as primary_source_type,

    r.company_norm,
    r.company_name,
    r.is_recruitment_agency,
    r.city_std,
    r.region_std,
    r.location_level,
    r.job_category,

    a.employment_type,
    a.workplace_type,
    a.remote_status,
    a.experience_level,
    a.experience_level_basis,

    r.job_title,
    r.title_norm,
    r.description_text,
    -- full, snippet (a Jooble snippet), or none when the posting has no description
    iff(r.description_text is null, 'none', r.description_basis)                  as description_basis,
    r.job_url,
    r.apply_url,
    a.salary_text,
    a.salary_is_parsed,
    a.salary_currency,
    a.salary_period,
    a.salary_min_amount,
    a.salary_max_amount,
    a.salary_min_sar_month,
    a.salary_max_sar_month,

    a.posting_date,
    a.first_seen_at,
    a.last_seen_at,
    a.is_active,
    a.status_basis,

    -- lifecycle (data_model.md, section 7.1)
    a.first_seen_date,
    a.last_seen_date,
    a.ats_last_seen_date,
    a.is_baseline,
    iff(a.is_baseline or a.ats_listings = 0, null, a.first_seen_date)              as opening_date,
    a.lifecycle_status,
    iff(a.lifecycle_status = 'disappeared', a.last_disappeared_date, null)         as disappeared_date,
    case
        when a.lifecycle_status = 'disappeared' then dateadd('day', -1, a.last_disappeared_date)
        else least(o.as_of_date, dateadd('day', {{ var('recent_window_days') }}, a.last_evidence_date))
    end                                                                            as open_until_date,
    iff(a.lifecycle_status = 'disappeared',
        datediff('day', coalesce(a.posting_date, a.first_seen_date), a.last_disappeared_date), null)
                                                                                   as days_listed,
    iff(a.lifecycle_status = 'disappeared',
        iff(a.posting_date is not null, 'posted', 'first_seen'), null)             as days_listed_basis,
    a.lifecycle_status <> 'disappeared'                                            as is_censored,
    o.as_of_date,

    a.match_tier,
    a.fuzzy_match_score,
    a.listing_count,
    a.listing_count_workable,
    a.listing_count_smartrecruiters,
    a.listing_count_ashby,
    a.listing_count_greenhouse,
    a.listing_count_jsearch,
    a.listing_count_jooble,
    a.copies_landed,
    a.source_count
from lifecycle a
join representative r
    on a.job_sk = r.job_sk
cross join as_of o