-- dbt/analyses/match_threshold_evaluation.sql
--
-- Chooses the fuzzy tier's function and threshold from the labelled pairs in seed_match_review
-- (data_model.md, section 8.7). For every threshold from 50 to 100 in steps of 5, and for each
-- score, it reports:
--   pairs_merged       labelled pairs the tier would merge (score >= threshold)
--   precision          share of those that are the same job
--   recall_in_sample   share of the labelled same-job pairs that would be merged
-- Pick the lowest threshold whose precision is acceptable, and state it with its precision,
-- recall and the number of labelled pairs, which is what the guide asks for ("a stated matching
-- strategy with its threshold and its error cases acknowledged"). Then set the two vars in
-- dbt_project.yml. Recall here is within the sample; overall recall stays a lower bound.

with labelled as (
    select
        c.jaccard_score,
        c.jaro_winkler_score,
        r.is_same_job
    from {{ ref('seed_match_review') }} r
    join {{ ref('int_match_candidates') }} c
        on (c.listing_a = r.listing_a and c.listing_b = r.listing_b)
        or (c.listing_a = r.listing_b and c.listing_b = r.listing_a)
),

thresholds as (
    select 50 + 5 * (row_number() over (order by seq4()) - 1) as threshold
    from table(generator(rowcount => 11))
),

scores as (
    select 'jaccard' as score_name, jaccard_score as score, is_same_job from labelled
    union all
    select 'jaro_winkler', jaro_winkler_score, is_same_job from labelled
)

select
    s.score_name,
    t.threshold,
    count(*)                                                        as labelled_pairs,
    count_if(s.score >= t.threshold)                                as pairs_merged,
    round(count_if(s.score >= t.threshold and s.is_same_job)
          / nullif(count_if(s.score >= t.threshold), 0), 3)         as precision,
    round(count_if(s.score >= t.threshold and s.is_same_job)
          / nullif(count_if(s.is_same_job), 0), 3)                  as recall_in_sample
from scores s
cross join thresholds t
group by s.score_name, t.threshold
order by s.score_name, t.threshold
