-- dbt/analyses/fuzzy_merge_audit.sql
--
-- Audit of the fuzzy tier (data_model.md, section 8.7): every job the fuzzy tier merged, with the
-- titles of all its listings and their sources, so a reviewer can mark each merge right or wrong.
-- The labelled sample (seed_match_review) chooses the threshold; this audit measures the precision
-- of the merges the tier actually made, after the mutual best match rule.
-- Deterministic order (hash of job_sk), so the same build lists the jobs in the same order; with
-- more merges than a reviewer can read, the first N rows are a fixed random sample.

select
    o.job_sk,
    o.company_name,
    o.city_std,
    o.fuzzy_match_score,
    listagg(distinct m.source_name || ': ' || m.job_title, ' || ')
        within group (order by m.source_name || ': ' || m.job_title)  as titles
from {{ ref('int_job_openings') }} o
join {{ ref('int_jobs_matched') }} m
    on m.job_sk = o.job_sk
where o.match_tier = 'fuzzy'
group by o.job_sk, o.company_name, o.city_std, o.fuzzy_match_score
order by hash(o.job_sk)
