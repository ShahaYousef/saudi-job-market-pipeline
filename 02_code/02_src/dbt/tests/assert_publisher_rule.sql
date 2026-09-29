-- dbt/tests/assert_publisher_rule.sql
-- Publisher rule (data_model.md, section 8.1): two postings that one publisher lists on one source
-- are never merged. Listings of one posting (the cities of a Workable posting that resolve to the
-- same location) may share a job, and so may one publisher's posting reached through two
-- aggregators; two different postings of one publisher on one source may not.
-- Every returned row is a job that holds two postings of one publisher on one source (= failure).
select job_sk, source_name, publisher, count(distinct posting_sk) as postings
from {{ ref('int_jobs_matched') }}
group by job_sk, source_name, publisher
having count(distinct posting_sk) > 1
