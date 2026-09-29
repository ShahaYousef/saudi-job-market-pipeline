-- dbt/models/marts/fct_jobs.sql
--
-- The fact table of the star schema (data_model.md, sections 4 and 7.1).
-- Grain: one job = one job advertisement in one Saudi location, after the listings of the same
-- job on several sources have been merged. Accumulating snapshot: one date role per milestone.
-- Every column comes from int_job_openings, which applies survivorship and lifecycle once.
--
-- Date roles (dim_date; -1 when the job has no such date):
--   posting_date_sk      posted: earliest employer-board posting date, else the earliest of any
--   first_seen_date_sk   first seen, last_seen_date_sk last seen (Asia/Riyadh dates)
--   opening_date_sk      opening: set only for a new opening (an employer-board job not seen in
--                        any baseline pull); Q7 groups it by week
--   open_until_date_sk   open until: last day the job counts as open. A job is open during a
--                        period when first_seen_date <= period end and open_until_date >= start
--   disappeared_date_sk  disappeared: set only when lifecycle_status = 'disappeared'; Q8
--
-- Measures:
--   job_count            1 per row (additive)
--   listing_count (+ 6)  listings merged into the job, in total and per source (additive)
--   copies_landed        landed copies of those listings in RAW (additive)
--   source_count         distinct sources among the listings (non-additive)
--   days_listed          disappeared jobs only; summarised by median, never summed (non-additive)
--   salary_*             salary as published (salary_text) and parsed; amounts are non-additive.
--                        Taken together from the first listing, by priority, that has a salary, which
--                        can be an aggregator copy of the job, so they live here and not in
--                        dim_job_posting
-- Jobs = SUM(job_count). Postings = COUNT(DISTINCT posting_sk). Through bridge_job_skill,
-- jobs = COUNT(DISTINCT job_sk).

select
    o.job_sk,
    o.posting_sk,
    case when o.company_norm is null then '-1'
         else {{ dbt_utils.generate_surrogate_key(['o.company_norm']) }} end              as company_sk,
    {{ dbt_utils.generate_surrogate_key(["coalesce(o.city_std, 'Unknown')",
                                         "coalesce(o.region_std, 'Unknown')",
                                         'o.location_level']) }}                          as location_sk,
    case when o.job_category = 'Unknown' then '-1'
         else {{ dbt_utils.generate_surrogate_key(['o.job_category']) }} end              as role_sk,
    case when o.employment_type = 'Unknown' and o.workplace_type = 'Unknown'
          and o.remote_status = 'Unknown' and o.experience_level = 'Unknown' then '-1'
         else {{ dbt_utils.generate_surrogate_key(['o.employment_type', 'o.workplace_type', 'o.remote_status',
                                                   'o.experience_level', 'o.experience_level_basis']) }}
    end                                                                                    as job_attributes_sk,
    {{ dbt_utils.generate_surrogate_key(['o.primary_source_name']) }}                      as primary_source_sk,

    coalesce(to_number(to_char(o.posting_date, 'YYYYMMDD')), -1)                       as posting_date_sk,
    coalesce(to_number(to_char(o.first_seen_date, 'YYYYMMDD')), -1)                    as first_seen_date_sk,
    coalesce(to_number(to_char(o.last_seen_date, 'YYYYMMDD')), -1)                     as last_seen_date_sk,
    coalesce(to_number(to_char(o.opening_date, 'YYYYMMDD')), -1)                       as opening_date_sk,
    coalesce(to_number(to_char(o.open_until_date, 'YYYYMMDD')), -1)                    as open_until_date_sk,
    coalesce(to_number(to_char(o.disappeared_date, 'YYYYMMDD')), -1)                   as disappeared_date_sk,

    o.lifecycle_status,
    o.status_basis,
    o.is_baseline,
    o.is_censored,
    o.match_tier,

    1                                                                                      as job_count,
    o.listing_count,
    o.listing_count_workable,
    o.listing_count_smartrecruiters,
    o.listing_count_ashby,
    o.listing_count_greenhouse,
    o.listing_count_jsearch,
    o.listing_count_jooble,
    o.copies_landed,
    o.source_count,
    o.days_listed,
    o.days_listed_basis,

    o.salary_text,
    o.salary_currency,
    o.salary_period,
    o.salary_min_amount,
    o.salary_max_amount,
    o.salary_min_sar_month,
    o.salary_max_sar_month
from {{ ref('int_job_openings') }} o
