-- dbt/models/intermediate/int_match_candidates.sql
--
-- Grain: one row per candidate pair of exact match groups (int_listing_groups) that the fuzzy
-- tier could merge. It holds every pair that passes the fixed rules, with both similarity scores,
-- and no threshold: the threshold is chosen from these pairs (data_model.md, section 8.7).
--
-- A pair is a candidate when:
--   - blocking: both groups have the same company_norm and city_std;
--   - the titles differ (equal titles are already one exact group);
--   - the two groups share no publisher on the same source (section 8.1 still holds after a merge);
--   - both titles carry the same level words (macros/matching.sql): "data analyst" never
--     meets "data analyst intern";
--   - one of the two scores is at least 50. This floor only keeps the table small; pairs below it
--     are never close to any threshold worth reviewing.
-- Both scores are kept so the labelled sample can compare them:
--   jaccard_score       shared distinct title words / all distinct title words, 0 to 100
--                       ("senior data analyst" / "data analyst" = 66.7)
--   jaro_winkler_score  Snowflake's JAROWINKLER_SIMILARITY, 0 to 100

with listings as (
    select
        *,
        -- the listing that stands for the group in a review: best source, then earliest, then
        -- source_record_sk. The last key breaks ties (one Jooble page lands every posting at the
        -- same second), so the same listing is chosen on every build and the labels in
        -- seed_match_review, keyed by listing_a and listing_b, keep joining.
        row_number() over (
            partition by match_group
            order by source_priority, first_seen_at, source_record_sk
        ) as group_rank
    from {{ ref('int_listing_groups') }}
    where is_matchable
),

groups as (
    select
        match_group,
        -- title_norm, company_norm and city_std define the group, so any value is the value
        any_value(title_norm)                                               as title_norm,
        any_value(company_norm)                                             as company_norm,
        any_value(city_std)                                                 as city_std,
        min(first_seen_at)                                                  as first_seen_at,
        max(iff(group_rank = 1, source_record_sk, null))                    as listing_id,
        max(iff(group_rank = 1, source_name, null))                         as source_name,
        max(iff(group_rank = 1, job_title, null))                           as job_title,
        {{ level_signature('any_value(title_norm)') }}                      as level_signature
    from listings
    group by match_group
),

group_publishers as (
    select distinct match_group, company_norm, city_std, publisher, source_name
    from listings
),

shared_publisher as (
    -- group pairs of one block that hold a listing of the same publisher on the same source:
    -- never merged
    select distinct a.match_group as match_group_a, b.match_group as match_group_b
    from group_publishers a
    join group_publishers b
        on  a.company_norm = b.company_norm
        and a.city_std = b.city_std
        and a.publisher = b.publisher
        and a.source_name = b.source_name
        and a.match_group < b.match_group
),

block_pairs as (
    select
        a.match_group                                                       as match_group_a,
        b.match_group                                                       as match_group_b
    from groups a
    join groups b
        on  a.company_norm = b.company_norm
        and a.city_std = b.city_std
        and a.match_group < b.match_group
        and a.level_signature = b.level_signature
    left join shared_publisher sp
        on  sp.match_group_a = a.match_group
        and sp.match_group_b = b.match_group
    where a.title_norm <> b.title_norm
      and sp.match_group_a is null
),

group_tokens as (
    select distinct g.match_group, t.value::string as token
    from groups g,
    lateral flatten(input => split(g.title_norm, ' ')) t
    where t.value::string <> ''
),

token_counts as (
    select match_group, count(*) as tokens
    from group_tokens
    group by match_group
),

shared_tokens as (
    select p.match_group_a, p.match_group_b, count(*) as tokens_shared
    from block_pairs p
    join group_tokens ta
        on ta.match_group = p.match_group_a
    join group_tokens tb
        on  tb.match_group = p.match_group_b
        and tb.token = ta.token
    group by p.match_group_a, p.match_group_b
),

scored as (
    select
        p.match_group_a,
        p.match_group_b,
        a.listing_id                                                        as listing_a,
        b.listing_id                                                        as listing_b,
        a.source_name                                                       as source_a,
        b.source_name                                                       as source_b,
        a.job_title                                                         as job_title_a,
        b.job_title                                                         as job_title_b,
        a.title_norm                                                        as title_norm_a,
        b.title_norm                                                        as title_norm_b,
        a.company_norm,
        a.city_std,
        a.level_signature,
        round(100 * coalesce(s.tokens_shared, 0)
              / (ca.tokens + cb.tokens - coalesce(s.tokens_shared, 0)), 1)  as jaccard_score,
        jarowinkler_similarity(a.title_norm, b.title_norm)                  as jaro_winkler_score,
        abs(datediff('day', a.first_seen_at, b.first_seen_at))              as first_seen_gap_days
    from block_pairs p
    join groups a         on a.match_group = p.match_group_a
    join groups b         on b.match_group = p.match_group_b
    join token_counts ca  on ca.match_group = p.match_group_a
    join token_counts cb  on cb.match_group = p.match_group_b
    left join shared_tokens s
        on  s.match_group_a = p.match_group_a
        and s.match_group_b = p.match_group_b
)

select
    {{ dbt_utils.generate_surrogate_key(['match_group_a', 'match_group_b']) }}  as candidate_sk,
    *
from scored
where jaccard_score >= 50
   or jaro_winkler_score >= 50
