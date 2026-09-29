-- dbt/tests/assert_fct_jobs_reconciles_with_listings.sql
-- The fact must account for every listing (data_model.md, section 10.1):
--   1. SUM(listing_count) equals the rows of int_job_listings
--   2. the six per-source counts add up to listing_count on every row
--   3. copies_landed >= listing_count on every row (each listing landed at least once)
-- Every returned row is a failure.
with totals as (
    select
        (select sum(listing_count) from {{ ref('fct_jobs') }})  as fact_listings,
        (select count(*) from {{ ref('int_job_listings') }})     as listings
)
select 'listing total' as check_name, null as job_sk
from totals
where fact_listings <> listings

union all

select 'per-source counts', job_sk
from {{ ref('fct_jobs') }}
where listing_count_workable + listing_count_smartrecruiters + listing_count_ashby
    + listing_count_greenhouse + listing_count_jsearch + listing_count_jooble <> listing_count

union all

select 'copies below listings', job_sk
from {{ ref('fct_jobs') }}
where copies_landed < listing_count