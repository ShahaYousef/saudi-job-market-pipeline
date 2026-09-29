-- dbt/tests/assert_job_survivorship.sql
-- Job keys and survivorship (data_model.md, sections 4, 8.4 to 8.6). Every returned row is a job
-- that breaks one of these rules:
--   1. one location and one employer per job: every listing of a job has the same company_norm,
--      city_std, region_std and location_level (the grain, and the blocking of section 8.3);
--   2. job_sk is the job's earliest listing: it is one of the job's listings, and no listing of
--      the job was first seen before it;
--   3. the representative listing has the job's best source priority;
--   4. an exact or single job is one exact group; a fuzzy job joins exactly two exact groups.
with listings as (
    select
        m.job_sk,
        m.source_record_sk,
        m.company_norm,
        m.city_std,
        m.region_std,
        m.location_level,
        m.first_seen_at,
        m.source_priority,
        m.is_representative,
        m.match_tier,
        g.match_group
    from {{ ref('int_jobs_matched') }} m
    join {{ ref('int_listing_groups') }} g
        on g.source_record_sk = m.source_record_sk
)

select
    job_sk,
    any_value(match_tier) as match_tier,
    count(*)              as listings
from listings
group by job_sk
having count(distinct coalesce(company_norm, '~')) > 1
    or count(distinct coalesce(city_std, '~')) > 1
    or count(distinct coalesce(region_std, '~')) > 1
    or count(distinct location_level) > 1
    or count_if(source_record_sk = job_sk) <> 1
    or min(first_seen_at) < min(iff(source_record_sk = job_sk, first_seen_at, null))
    or min(source_priority) <> min(iff(is_representative, source_priority, null))
    or (max(match_tier) = 'fuzzy' and count(distinct match_group) <> 2)
    or (max(match_tier) <> 'fuzzy' and count(distinct match_group) <> 1)
