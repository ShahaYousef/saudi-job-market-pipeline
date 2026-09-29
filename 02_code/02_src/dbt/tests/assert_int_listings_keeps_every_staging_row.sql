-- dbt/tests/assert_int_listings_keeps_every_staging_row.sql
-- The union must neither drop nor duplicate listings: int_job_listings must have exactly as many
-- rows as the six staging models together. Returns a row (= failure) when the counts differ.
select
    s.n as staging_rows,
    i.n as intermediate_rows
from (
    select sum(n) as n
    from (
        select count(*) as n from {{ ref('stg_ashby_jobs') }}
        union all
        select count(*) from {{ ref('stg_workable_jobs') }}
        union all
        select count(*) from {{ ref('stg_greenhouse_jobs') }}
        union all
        select count(*) from {{ ref('stg_smartrecruiters_jobs') }}
        union all
        select count(*) from {{ ref('stg_jsearch_jobs') }}
        union all
        select count(*) from {{ ref('stg_jooble_jobs') }}
    ) per_source
) s
cross join (
    select count(*) as n from {{ ref('int_job_listings') }}
) i
where s.n <> i.n