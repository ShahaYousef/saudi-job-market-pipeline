-- dbt/analyses/match_review_sample.sql
-- 40 cross-source pairs that matching merged into one opening, drawn deterministically, for a manual
-- precision review (data_model.md, section 8.7). Record the verdicts in dbt/seeds/seed_match_review.csv:
--   listing_a,listing_b,is_same_job,reviewer
select
    a.source_record_sk as listing_a,
    b.source_record_sk as listing_b,
    a.source_name      as source_a,
    b.source_name      as source_b,
    a.job_title        as title_a,
    b.job_title        as title_b,
    a.company_raw      as company_a,
    b.company_raw      as company_b,
    a.location_raw     as location_a,
    b.location_raw     as location_b
from {{ ref('int_jobs_matched') }} a
join {{ ref('int_jobs_matched') }} b
  on  a.job_sk = b.job_sk
  and a.is_representative
  and not b.is_representative
where a.source_name <> b.source_name
order by hash(a.source_record_sk, b.source_record_sk)
limit 40
