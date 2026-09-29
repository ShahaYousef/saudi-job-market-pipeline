-- dbt/models/intermediate/int_job_listings.sql
--
-- Grain: one row per listing (one posting on one source; for Workable, one posting in one city).
-- Same grain as the six staging models combined. Input to int_listing_groups and int_jobs_matched.
--
-- Steps (data_model.md, sections 6, 7.1 and 8.2):
--   1. unioned        the six staging models on one shared column list. Each source's own
--                     columns are mapped by hand (Greenhouse brand, Workable telecommuting and
--                     experience, SmartRecruiters experience_level, JSearch publisher and
--                     is_remote, Jooble underlying_source and salary).
--   2. standardized   source metadata from seed_sources, publisher, company through
--                     seed_company_aliases, source experience through seed_experience_levels,
--                     remote_status, plain-text description, matching keys, dates in
--                     Asia/Riyadh, salary parsed into amounts, currency and period.
--   3. city_*         seed_city_mapping lookup: city field first, then location text. A text that
--                     names several cities is not given the first one: it is kept at the region
--                     the cities share, else at country level ("Riyadh or Jeddah" is one job whose
--                     city is not fixed).
--   4. category_hits  seed_job_categories lookup with a deterministic tie-break.
--   5. seniority_hits seed_seniority_keywords on the title, used when the source gives no level.
--   6. lifecycle      baseline and disappearance evidence from the pull calendar (int_board_pulls).
--
-- is_active: known for ATS listings only (a board file lists every open job, so a posting missing
-- from the latest pull of its own board was taken down). Aggregator listings get null (unknown):
-- a query returns a ranked slice of the market, not a full list, so a listing that a later run did
-- not return may still be open.

with unioned as (

    select source_record_sk, source_name, source_job_id,
           company_raw, title_raw, location_raw, city_raw, region_raw, country_raw,
           workplace_type_raw, employment_type,
           is_remote                          as is_remote,
           null::string                       as experience_raw,
           null::string                       as industry_raw,
           {{ board_from_path('file_name') }} as publisher_raw,
           {{ board_from_path('file_name') }} as board,
           null::string                       as salary_raw,
           description_plain, job_url, apply_url,
           posting_date_raw::timestamp_tz     as posting_date_raw,
           first_seen_at::timestamp_tz        as first_seen_at,
           last_seen_at::timestamp_tz         as last_seen_at,
           copies_landed,
           is_active
    from {{ ref('stg_ashby_jobs') }}

    union all
    select source_record_sk, source_name, source_job_id,
           company_raw, title_raw, location_raw, city_raw, region_raw, country_raw,
           workplace_type_raw, employment_type,
           telecommuting,                     -- Workable's remote flag
           experience,
           industry,
           {{ board_from_path('file_name') }},
           {{ board_from_path('file_name') }},
           null::string,
           description_plain, job_url, apply_url,
           posting_date_raw::timestamp_tz,
           first_seen_at::timestamp_tz,
           last_seen_at::timestamp_tz,
           copies_landed,
           is_active
    from {{ ref('stg_workable_jobs') }}

    union all
    select source_record_sk, source_name, source_job_id,
           coalesce(brand_raw, company_raw),  -- umbrella boards list the jobs of their brands
           title_raw, location_raw, city_raw, region_raw, country_raw,
           workplace_type_raw, employment_type,
           null::boolean,
           null::string,
           null::string,
           {{ board_from_path('file_name') }},
           {{ board_from_path('file_name') }},
           null::string,
           description_plain, job_url, apply_url,
           posting_date_raw::timestamp_tz,
           first_seen_at::timestamp_tz,
           last_seen_at::timestamp_tz,
           copies_landed,
           is_active
    from {{ ref('stg_greenhouse_jobs') }}

    union all
    select source_record_sk, source_name, source_job_id,
           company_raw, title_raw, location_raw, city_raw, region_raw, country_raw,
           workplace_type_raw, employment_type,
           null::boolean,                     -- remote and hybrid are already in workplace_type_raw
           experience_level,
           industry_label,
           {{ board_from_path('file_name') }},
           {{ board_from_path('file_name') }},
           null::string,
           description_plain, job_url, apply_url,
           posting_date_raw::timestamp_tz,
           first_seen_at::timestamp_tz,
           last_seen_at::timestamp_tz,
           copies_landed,
           is_active
    from {{ ref('stg_smartrecruiters_jobs') }}

    union all
    select source_record_sk, source_name, source_job_id,
           company_raw, title_raw, location_raw, city_raw, region_raw, country_raw,
           workplace_type_raw, employment_type,
           is_remote,
           null::string,
           null::string,
           job_publisher,
           'jsearch',                         -- an aggregator is pulled as a whole source
           salary_raw,
           description_plain, job_url, apply_url,
           posting_date_raw::timestamp_tz,
           first_seen_at::timestamp_tz,
           last_seen_at::timestamp_tz,
           copies_landed,
           null::boolean                      -- aggregators carry no status (see the header)
    from {{ ref('stg_jsearch_jobs') }}

    union all
    select source_record_sk, source_name, source_job_id,
           company_raw, title_raw, location_raw, city_raw, region_raw, country_raw,
           workplace_type_raw, employment_type,
           null::boolean,
           null::string,
           null::string,
           underlying_source,
           'jooble',
           salary_raw,
           description_plain, job_url, apply_url,
           posting_date_raw::timestamp_tz,
           first_seen_at::timestamp_tz,
           last_seen_at::timestamp_tz,
           copies_landed,
           null::boolean
    from {{ ref('stg_jooble_jobs') }}
),

standardized as (
    select
        u.source_record_sk,
        u.source_name,
        src.source_type,
        src.source_priority,
        u.source_job_id,
        u.board,

        -- One posting across its cities: Workable repeats the shortcode for every city, so the
        -- city is left out. For every other source this equals source_record_sk.
        {{ dbt_utils.generate_surrogate_key(['u.source_name', 'u.source_job_id']) }}   as posting_sk,

        -- Publisher (Section 8.1). ATS: the employer's own board. Aggregators: the site the
        -- listing came through, normalized so "Jobrapido" and "Jobrapido.com" are one publisher.
        case
            when src.source_type = 'ATS'
                then u.source_name || ':' || coalesce(u.publisher_raw, 'unknown')
            else coalesce(
                nullif(regexp_replace(
                    regexp_replace(lower(trim(u.publisher_raw)), '^www\\.|\\.(com|net|org|io|co|sa)$', ''),
                    '[[:space:][:punct:]]', ''), ''),
                u.source_name || ':unknown')
        end                                                                          as publisher,

        -- company: placeholders (Private Company, Confidential) and missing names become Unknown
        case
            when co.company_std = 'Unknown' or {{ normalize_company('u.company_raw') }} is null then 'Unknown'
            else coalesce(co.company_std, trim(u.company_raw))
        end                                                                          as company_name,
        coalesce(co.is_recruitment_agency, false)                                    as is_recruitment_agency,
        co.alias is not null                                                         as company_in_seed,
        u.company_raw,

        trim(u.title_raw)                                                            as job_title,
        {{ normalize_title('u.title_raw') }}                                         as title_norm,

        u.location_raw,
        u.city_raw,
        u.region_raw,
        u.country_raw,
        {{ normalize_text('u.city_raw') }}                                           as city_norm,
        {{ normalize_text("array_to_string(array_construct_compact(u.location_raw, u.region_raw), ' , ')") }}
                                                                                     as location_norm,

        coalesce(u.employment_type, 'Unknown')                                       as employment_type,
        coalesce(u.workplace_type_raw, 'Unknown')                                    as workplace_type,
        -- workplace_type first, so Ashby's Hybrid jobs (sent with isRemote = true) are Not remote,
        -- as on SmartRecruiters; the true / false flags only when it is unknown
        case
            when u.workplace_type_raw = 'Remote'              then 'Remote'
            when u.workplace_type_raw in ('Hybrid', 'OnSite') then 'Not remote'
            when u.is_remote = true                           then 'Remote'
            when u.is_remote = false                          then 'Not remote'
            else 'Unknown'
        end                                                                          as remote_status,

        -- level given by the source. Unmapped values pass through unchanged, so the
        -- accepted_values test on experience_level catches them
        case
            when nullif(trim(u.experience_raw), '') is null then 'Unknown'
            else coalesce(ex.experience_level, trim(u.experience_raw))
        end                                                                          as experience_level_source,
        nullif(trim(u.industry_raw), '')                                             as industry,

        {{ strip_html('u.description_plain') }}                                      as description_text,
        -- Jooble returns a short snippet, every other source the full text; skill shares use
        -- full descriptions only (data_model.md, Q9)
        iff(u.source_name = 'jooble', 'snippet', 'full')                             as description_basis,
        u.job_url,
        u.apply_url,
        nullif(trim(u.salary_raw), '')                                               as salary_text,

        -- dates in the business time zone (var business_timezone)
        convert_timezone('{{ var("business_timezone") }}', u.posting_date_raw)::date as posting_date,
        u.first_seen_at,
        u.last_seen_at,
        convert_timezone('{{ var("business_timezone") }}', u.first_seen_at)::date   as first_seen_date,
        convert_timezone('{{ var("business_timezone") }}', u.last_seen_at)::date    as last_seen_date,
        u.copies_landed,
        u.is_active                                                                  as is_active_staging

    from unioned u
    left join {{ ref('seed_sources') }} src
        on u.source_name = src.source_name
    left join {{ ref('seed_company_aliases') }} co
        on {{ normalize_company('u.company_raw') }} = co.alias
    left join {{ ref('seed_experience_levels') }} ex
        on lower(trim(u.experience_raw)) = ex.raw_value
),

salary as (
    -- Every salary text observed (371 in the final build) follows one grammar:
    -- currency, amount or range, period, e.g. "SAR 15000 - 17000 per month", "$10 per hour".
    -- A text outside it is left unparsed (salary_is_parsed = false) and counted by the tests.
    select
        source_record_sk,
        salary_text,
        regexp_like(salary_text, '^(SAR |\\$)[0-9][0-9,.]*( - \\$?[0-9][0-9,.]*)? per (hour|day|week|month|year)$')
                                                                                     as salary_is_parsed,
        case when salary_text like 'SAR %' then 'SAR' when salary_text like '$%' then 'USD' end
                                                                                     as salary_currency,
        regexp_substr(salary_text, 'per (hour|day|week|month|year)$', 1, 1, 'e', 1)  as salary_period,
        try_to_number(replace(regexp_substr(salary_text, '[0-9][0-9,.]*', 1, 1), ',', ''), 18, 2)
                                                                                     as amount_1,
        try_to_number(replace(regexp_substr(salary_text, '[0-9][0-9,.]*', 1, 2), ',', ''), 18, 2)
                                                                                     as amount_2
    from standardized
    where salary_text is not null
),

salary_parsed as (
    select
        s.source_record_sk,
        s.salary_is_parsed,
        iff(s.salary_is_parsed, s.salary_currency, null)                             as salary_currency,
        iff(s.salary_is_parsed, s.salary_period, null)                               as salary_period,
        iff(s.salary_is_parsed, s.amount_1, null)                                    as salary_min_amount,
        iff(s.salary_is_parsed, coalesce(s.amount_2, s.amount_1), null)              as salary_max_amount,
        -- to SAR per year: month x12, week x52, year x1. The monthly amount divides this by 12 at
        -- the end, because 1 / 12 on its own keeps six decimals in Snowflake and turned
        -- $45000 a year into 14,062 SAR a month instead of 14,063. Hour and day are not
        -- converted, because the hours and days worked per month are unknown.
        case s.salary_period
            when 'month' then 12
            when 'year'  then 1
            when 'week'  then 52
        end * fx.sar_per_unit                                                        as to_sar_year
    from salary s
    left join {{ ref('seed_currency_rates') }} fx
        on s.salary_currency = fx.currency
),

city_hits_all as (
    -- every seed alias found as a whole word in the city field or in the location text
    select
        s.source_record_sk,
        m.alias,
        m.city_std,
        m.region_std,
        coalesce(' ' || s.city_norm || ' ' like '% ' || m.alias || ' %', false)     as in_city_field,
        position(' ' || m.alias || ' ' in ' ' || iff(coalesce(' ' || s.city_norm || ' ' like '% ' || m.alias || ' %', false),
                                                    s.city_norm, s.location_norm) || ' ')
                                                                                     as hit_start,
        length(m.alias)                                                              as hit_length
    from standardized s
    join {{ ref('seed_city_mapping') }} m
        on ' ' || s.city_norm || ' '     like '% ' || m.alias || ' %'
        or ' ' || s.location_norm || ' ' like '% ' || m.alias || ' %'
),

city_hits_kept as (
    -- a hit inside a longer hit of the same text is part of it, not a second place:
    -- "makkah" inside "makkah province" is the region, not the city of Makkah
    select h.*
    from city_hits_all h
    where not exists (
        select 1
        from city_hits_all o
        where o.source_record_sk = h.source_record_sk
          and o.in_city_field = h.in_city_field
          and o.hit_length > h.hit_length
          and o.hit_start <= h.hit_start
          and o.hit_start + o.hit_length >= h.hit_start + h.hit_length
    )
),

city_candidates as (
    -- the city field wins; the location text is used only when the city field matches nothing
    select *
    from city_hits_kept
    qualify in_city_field = boolor_agg(in_city_field) over (partition by source_record_sk)
),

city_hits as (
    select
        source_record_sk,
        count(distinct city_std) over (partition by source_record_sk)                as cities_named,
        count(distinct iff(city_std is not null, region_std, null))
            over (partition by source_record_sk)                                     as city_regions_named,
        max(iff(city_std is not null, region_std, null))
            over (partition by source_record_sk)                                     as city_region,
        city_std,
        region_std
    from city_candidates
    -- a city before a region, so "Eastern Province, Dammam" keeps Dammam; then the earliest
    -- mention, the longer alias, and the alias itself
    qualify row_number() over (
        partition by source_record_sk
        order by iff(city_std is null, 1, 0), hit_start, hit_length desc, alias
    ) = 1
),

category_hits as (
    -- lowest priority wins; ties go to the longer keyword, then to the category name,
    -- so a title always gets the same category (e.g. "Planning Engineer")
    select
        s.source_record_sk,
        c.job_category
    from standardized s
    join {{ ref('seed_job_categories') }} c
        on ' ' || s.title_norm || ' ' like '% ' || c.keyword || ' %'
    qualify row_number() over (
        partition by s.source_record_sk
        order by c.priority, length(c.keyword) desc, c.job_category
    ) = 1
),

seniority_hits as (
    -- level words in the title. A rule is kept only when postings whose source gives a level
    -- agree with it at least 70% of the time (seed_seniority_keywords records the measurement).
    -- A row without a level ("assistant manager", 45%) blocks the weaker rules below it.
    select
        s.source_record_sk,
        k.experience_level
    from standardized s
    join {{ ref('seed_seniority_keywords') }} k
        on ' ' || s.title_norm || ' ' like '% ' || k.keyword || ' %'
    qualify row_number() over (
        partition by s.source_record_sk
        order by k.priority, length(k.keyword) desc, k.keyword
    ) = 1
),

pull_calendar as (
    select * from {{ ref('int_board_pulls') }}
    where is_successful
),

board_calendar as (
    select source_name, board, max(pull_date) as latest_successful_pull
    from pull_calendar
    group by source_name, board
),

enriched as (
    select
        s.* exclude (city_norm, location_norm, is_active_staging, experience_level_source),

        -- Matching key for the company: the standard name, normalized, so every alias of a company
        -- gives the same key. Null for Unknown, so such listings are never matched.
        case
            when s.company_name = 'Unknown' then null
            else {{ normalize_company('s.company_name') }}
        end                                                                          as company_norm,

        iff(coalesce(ch.cities_named, 0) > 1, null, ch.city_std)                     as city_std,
        case
            when coalesce(ch.cities_named, 0) <= 1 then ch.region_std
            when ch.city_regions_named = 1         then ch.city_region
        end                                                                          as region_std,
        coalesce(ch.cities_named, 0)                                                 as cities_named,

        case
            when s.title_norm is null then 'Unknown'
            else coalesce(cat.job_category, 'Other')
        end                                                                          as job_category,

        -- level: the source's own field first, then the title, else Unknown
        case
            when s.experience_level_source <> 'Unknown' then s.experience_level_source
            when sen.experience_level is not null     then sen.experience_level
            else 'Unknown'
        end                                                                          as experience_level,
        case
            when s.experience_level_source <> 'Unknown' then 'source'
            when sen.experience_level is not null     then 'title'
            else 'unknown'
        end                                                                          as experience_level_basis,

        sp.salary_is_parsed,
        sp.salary_currency,
        sp.salary_period,
        sp.salary_min_amount,
        sp.salary_max_amount,
        round(sp.salary_min_amount * sp.to_sar_year / 12, 0)                         as salary_min_sar_month,
        round(sp.salary_max_amount * sp.to_sar_year / 12, 0)                         as salary_max_sar_month,

        -- ATS: from staging (absent from the latest pull of its own board = taken down).
        -- Aggregators: null = unknown.
        s.is_active_staging                                                          as is_active
    from standardized s
    left join city_hits ch
        on s.source_record_sk = ch.source_record_sk
    left join category_hits cat
        on s.source_record_sk = cat.source_record_sk
    left join seniority_hits sen
        on s.source_record_sk = sen.source_record_sk
    left join salary_parsed sp
        on s.source_record_sk = sp.source_record_sk
),

missed_pulls as (
    -- successful pulls of the listing's own board after the last day it was seen (ATS only)
    select
        e.source_record_sk,
        count(*)            as board_pulls_missed,
        min(p.pull_date)    as first_missed_pull_date
    from enriched e
    join pull_calendar p
        on  p.source_name = e.source_name
        and p.board = e.board
        and p.pull_date > e.last_seen_date
    where e.source_type = 'ATS'
    group by e.source_record_sk
)

select
    e.* exclude (city_std, region_std, cities_named),
    e.city_std,
    e.region_std,
    case
        when e.city_std is not null   then 'city'
        when e.region_std is not null then 'region'
        else 'country'
    end                                                                              as location_level,
    'SA'                                                                             as country_std,
    e.cities_named,

    -- lifecycle evidence (data_model.md, section 7.1)
    base.pull_date is not null                                                       as is_baseline,
    bc.latest_successful_pull                                                        as board_latest_successful_pull,
    iff(e.source_type = 'ATS', coalesce(mp.board_pulls_missed, 0), null)             as board_pulls_missed,
    -- disappeared: staging saw it leave its board, and K successful pulls confirm it
    case
        when e.source_type <> 'ATS' then null
        else coalesce(e.is_active = false
                      and coalesce(mp.board_pulls_missed, 0) >= {{ var('disappearance_misses') }}, false)
    end                                                                              as is_disappeared,
    iff(e.is_active = false and coalesce(mp.board_pulls_missed, 0) >= {{ var('disappearance_misses') }},
        mp.first_missed_pull_date, null)                                             as disappeared_date,
    -- last day the listing is known to be open: its board's latest successful pull for an ATS
    -- listing still open; its last sighting for an aggregator listing
    case
        when e.source_type = 'ATS'
             and e.is_active = false
             and coalesce(mp.board_pulls_missed, 0) >= {{ var('disappearance_misses') }} then null
        when e.source_type = 'ATS' then greatest(e.last_seen_date, coalesce(bc.latest_successful_pull, e.last_seen_date))
        else e.last_seen_date
    end                                                                              as last_evidence_date
from enriched e
left join board_calendar bc
    on  bc.source_name = e.source_name
    and bc.board = e.board
left join pull_calendar base
    on  base.source_name = e.source_name
    and base.board = e.board
    and base.pull_date = e.first_seen_date
    and base.is_baseline_pull
left join missed_pulls mp
    on e.source_record_sk = mp.source_record_sk
