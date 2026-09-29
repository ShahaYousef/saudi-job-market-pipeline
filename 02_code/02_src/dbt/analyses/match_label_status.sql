-- dbt/analyses/match_label_status.sql
--
-- Where each labelled pair of seed_match_review stands on the current build (data_model.md,
-- section 8.7). A label keeps its value only while its pair is still a fuzzy candidate; a change to
-- the title key can move a pair into the exact tier or out of the candidates. One row per status:
--   candidate                 still a pair in int_match_candidates (used by match_threshold_evaluation)
--   same job, not a candidate the two listings are now in one job (for example, an exact merge)
--   two jobs, not a candidate the two listings are in two jobs and no longer compared
-- A pair labelled "not the same job" that is now in one job is a false merge to look at.

with labels as (
    select
        r.listing_a,
        r.listing_b,
        r.is_same_job,
        a.job_sk    as job_a,
        b.job_sk    as job_b,
        a.job_title as title_a,
        b.job_title as title_b,
        c.candidate_sk is not null as is_candidate
    from {{ ref('seed_match_review') }} r
    left join {{ ref('int_jobs_matched') }} a on a.source_record_sk = r.listing_a
    left join {{ ref('int_jobs_matched') }} b on b.source_record_sk = r.listing_b
    left join {{ ref('int_match_candidates') }} c
        on (c.listing_a = r.listing_a and c.listing_b = r.listing_b)
        or (c.listing_a = r.listing_b and c.listing_b = r.listing_a)
)

select
    case
        when is_candidate   then 'candidate'
        when job_a = job_b  then 'same job, not a candidate'
        else 'two jobs, not a candidate'
    end                                                        as status,
    is_same_job                                                as labelled_same_job,
    count(*)                                                   as pairs,
    listagg(title_a || ' || ' || title_b, ' ## ')
        within group (order by title_a, title_b)               as titles
from labels
group by 1, 2
order by 1, 2
