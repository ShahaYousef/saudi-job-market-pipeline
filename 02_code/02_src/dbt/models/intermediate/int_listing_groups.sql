-- dbt/models/intermediate/int_listing_groups.sql
--
-- Grain: one row per listing, with its exact match group. Tier 1 of cross-source matching
-- (data_model.md, section 8.4); int_jobs_matched adds the fuzzy tier and the job keys.
--
--   1. Match key: title_norm + company_norm + city_std, all three known. A listing missing any
--      of them is never matched and forms a group of its own.
--   2. Publisher rule (section 8.1): two postings that one publisher lists on one source are never
--      merged. Inside one match key, the postings of each publisher on each source are ranked
--      (posting date, first seen, posting_sk) and paired rank to rank: the first posting of every
--      publisher forms one group, the second posting of every publisher the next one, and so on.
--      So an employer's two identical-looking postings stay two jobs, and each can still take an
--      aggregator copy. The source is part of the rule because the same publisher reached through
--      two aggregators is one posting seen twice, not two postings: a JobLeads posting returned by
--      both JSearch and Jooble is one job (49 such keys on 2026-09-28, each with the same text).
--      The ranking is per posting, not per listing: when two cities of one Workable posting
--      resolve to the same location (two spellings of one city), they are one job, because the
--      grain is one posting in one location. Listings that cannot be matched (no company, city
--      or title) are grouped the same way, by posting and location.

with listings as (
    select * from {{ ref('int_job_listings') }}
),

posting_order as (
    -- one ordering value per posting, shared by all of its listings
    select
        *,
        min(posting_date)  over (partition by posting_sk) as posting_first_date,
        min(first_seen_at) over (partition by posting_sk) as posting_first_seen
    from listings
),

ranked as (
    select
        *,
        title_norm is not null and company_norm is not null and city_std is not null as is_matchable,
        dense_rank() over (
            partition by title_norm, company_norm, city_std, publisher, source_name
            order by posting_first_date nulls last, posting_first_seen, posting_sk
        ) as publisher_rank
    from posting_order
),

grouped as (
    select
        *,
        case
            when is_matchable
                then md5(title_norm || '|' || company_norm || '|' || city_std || '|' || publisher_rank)
            else md5(posting_sk || '|' || coalesce(city_std, '') || '|' || coalesce(region_std, '') || '|' || location_level)
        end as match_group
    from ranked
)

select
    match_group,
    count(*) over (partition by match_group)                                 as exact_group_size,
    -- several postings in the group: two cities of one Workable posting that resolve to the same
    -- location are one posting, so they do not make an exact match
    min(posting_sk) over (partition by match_group)
        <> max(posting_sk) over (partition by match_group)                  as exact_group_has_postings,
    * exclude (match_group, publisher_rank, posting_first_date, posting_first_seen)
from grouped
