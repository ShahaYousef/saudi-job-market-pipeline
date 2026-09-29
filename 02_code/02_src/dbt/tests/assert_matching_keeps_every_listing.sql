-- dbt/tests/assert_matching_keeps_every_listing.sql
-- Matching must neither drop nor duplicate listings: every listing belongs to exactly one opening.
select l.n as listings, m.n as matched
from (select count(*) as n from {{ ref('int_job_listings') }}) l
cross join (select count(*) as n from {{ ref('int_jobs_matched') }}) m
where l.n <> m.n