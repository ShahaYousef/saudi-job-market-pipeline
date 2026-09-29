-- dbt/models/intermediate/int_jobs_matched.sql
--
-- Grain: one row per listing, same as int_job_listings, with the job it belongs to.
-- Cross-source matching as specified in data_model.md, section 8:
--
--   Tier 1  exact: int_listing_groups (title_norm + company_norm + city_std, publisher rule,
--           rank-to-rank pairing).
--   Tier 2  fuzzy: two exact groups from int_match_candidates are merged when their score
--           reaches var('fuzzy_match_threshold') and each is the other's best candidate
--           (mutual best match). Every group has one best candidate, so a group joins at most
--           one other group: pairs cannot chain (A~B, B~C) into a job that holds two postings of
--           one publisher on one source. Ties go to the higher score, then the closer first-seen
--           dates, then the group key. The function and the threshold are dbt vars chosen from the
--           labelled sample (Jaccard at 80, dbt_project.yml); a null threshold turns the tier off.
--
--   job_sk             source_record_sk of the job's anchor, its earliest listing (first seen, then
--                      source_record_sk). Stable as long as the anchor stays in the same job.
--   is_representative  the listing whose values represent the job, chosen by source_priority
--                      (seed_sources), then first seen, then source_record_sk.
--   match_tier         'fuzzy' when the tier-2 merge applied, 'exact' when the exact group holds
--                      several postings, 'single' otherwise (the cities of one Workable posting
--                      that resolve to one location are one posting, not a match).

{% set fn = var('fuzzy_match_function') %}
{% set threshold = var('fuzzy_match_threshold') %}
{% if threshold is not none and fn not in ['jaccard', 'jaro_winkler'] %}
    {{ exceptions.raise_compiler_error("fuzzy_match_threshold is set, so fuzzy_match_function must be 'jaccard' or 'jaro_winkler', got: " ~ fn) }}
{% endif %}

with listings as (
    select * from {{ ref('int_listing_groups') }}
),

{% if threshold is not none %}
scored as (
    select
        match_group_a,
        match_group_b,
        {{ 'jaccard_score' if fn == 'jaccard' else 'jaro_winkler_score' }}  as score,
        first_seen_gap_days
    from {{ ref('int_match_candidates') }}
    where {{ 'jaccard_score' if fn == 'jaccard' else 'jaro_winkler_score' }} >= {{ threshold }}
),

directed as (
    select match_group_a as match_group, match_group_b as other_group, score, first_seen_gap_days from scored
    union all
    select match_group_b, match_group_a, score, first_seen_gap_days from scored
),

best as (
    select *
    from directed
    qualify row_number() over (
        partition by match_group
        order by score desc, first_seen_gap_days, other_group
    ) = 1
),

fuzzy_merges as (
    select
        b1.match_group,
        least(b1.match_group, b1.other_group)                               as merged_group,
        b1.score                                                            as fuzzy_match_score
    from best b1
    join best b2
        on  b1.match_group = b2.other_group
        and b1.other_group = b2.match_group
),
{% else %}
fuzzy_merges as (
    select null::string as match_group, null::string as merged_group, null::number(5, 1) as fuzzy_match_score
    where 1 = 0
),
{% endif %}

final_groups as (
    select
        l.*,
        coalesce(f.merged_group, l.match_group)                             as final_group,
        case
            when f.match_group is not null then 'fuzzy'
            when l.exact_group_has_postings  then 'exact'
            else 'single'
        end                                                                 as match_tier,
        f.fuzzy_match_score
    from listings l
    left join fuzzy_merges f
        on l.match_group = f.match_group
)

select
    first_value(source_record_sk) over (
        partition by final_group
        order by first_seen_at, source_record_sk
    )                                                                        as job_sk,
    row_number() over (
        partition by final_group
        order by source_priority, first_seen_at, source_record_sk
    ) = 1                                                                    as is_representative,
    count(*) over (partition by final_group)                                 as listings_in_job,
    * exclude (match_group, final_group, exact_group_size, exact_group_has_postings)
from final_groups
