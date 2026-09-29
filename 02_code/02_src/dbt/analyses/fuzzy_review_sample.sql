-- dbt/analyses/fuzzy_review_sample.sql
--
-- Pairs to label by hand before the fuzzy tier is switched on (data_model.md, section 8.7).
-- Stratified: up to 10 pairs from every 10-point band of each score, from 50 to 100, so the
-- sample covers the whole range where a threshold could sit, not only the easy top.
-- Record each verdict in seeds/seed_match_review.csv:
--   listing_a,listing_b,is_same_job,reviewer
-- then run analyses/match_threshold_evaluation.sql.
-- Deterministic: the same build gives the same sample.

with bands as (
    select
        *,
        'jaccard'     as score_name,
        floor(jaccard_score / 10) * 10 as band
    from {{ ref('int_match_candidates') }}
    where jaccard_score >= 50

    union all

    select
        *,
        'jaro_winkler',
        floor(jaro_winkler_score / 10) * 10
    from {{ ref('int_match_candidates') }}
    where jaro_winkler_score >= 50
),

sampled as (
    select *
    from bands
    qualify row_number() over (partition by score_name, band order by hash(candidate_sk)) <= 10
)

select distinct
    listing_a,
    listing_b,
    source_a,
    source_b,
    company_norm,
    city_std,
    job_title_a,
    job_title_b,
    jaccard_score,
    jaro_winkler_score
from sampled
order by jaccard_score desc, jaro_winkler_score desc
