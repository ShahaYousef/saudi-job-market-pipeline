-- dbt/analyses/intermediate_checks.sql
--
-- One result set of checks on the built intermediate layer (data_model.md, section 10). Run after
-- `dbt build --select intermediate` and paste the result into the quality report.
-- Each row: check, value, and what it should be.

select 'listings = sum of staging' as check_name,
       (select count(*) from {{ ref('int_job_listings') }})::varchar as value,
       ((select count(*) from {{ ref('stg_ashby_jobs') }}) + (select count(*) from {{ ref('stg_workable_jobs') }})
      + (select count(*) from {{ ref('stg_greenhouse_jobs') }}) + (select count(*) from {{ ref('stg_smartrecruiters_jobs') }})
      + (select count(*) from {{ ref('stg_jsearch_jobs') }}) + (select count(*) from {{ ref('stg_jooble_jobs') }}))::varchar as expected
union all
select 'jobs', (select count(*) from {{ ref('int_job_openings') }})::varchar, 'fewer than listings'
union all
select 'jobs by match tier: ' || match_tier, count(*)::varchar, 'fuzzy = the jobs listed by analyses/fuzzy_merge_audit.sql (51 on 28 Sep)'
from {{ ref('int_job_openings') }} group by match_tier
union all
select 'fuzzy candidate pairs', (select count(*) from {{ ref('int_match_candidates') }})::varchar, 'scored pairs; seed_match_review labels a sample of them'
union all
select 'listings at location level: ' || location_level, count(*)::varchar, 'city for most'
from {{ ref('int_job_listings') }} group by location_level
union all
select 'listings naming several cities', count_if(cities_named > 1)::varchar, 'a handful (5 on 28 Sep), none given a city'
from {{ ref('int_job_listings') }}
union all
select 'listings kept at region level although one city is named', count_if(location_level = 'region' and cities_named = 1)::varchar,
       '0: a city is preferred over a region'
from {{ ref('int_job_listings') }}
union all
select 'match keys where one publisher reached through JSearch and Jooble is still two jobs', count(*)::varchar,
       '0: the publisher rule applies per source'
from (
    select title_norm, company_norm, city_std, publisher
    from {{ ref('int_jobs_matched') }}
    where source_type = 'Aggregator'
      and title_norm is not null and company_norm is not null and city_std is not null
    group by title_norm, company_norm, city_std, publisher
    having count(distinct source_name) > 1 and count(distinct job_sk) > 1
) k
union all
select 'jobs by experience basis: ' || experience_level_basis, count(*)::varchar, 'title adds coverage'
from {{ ref('int_job_openings') }} group by experience_level_basis
union all
select 'salary texts / parsed', count(salary_text)::varchar || ' / ' || count_if(salary_is_parsed)::varchar, 'equal'
from {{ ref('int_job_listings') }}
union all
select 'jobs by lifecycle: ' || lifecycle_status, count(*)::varchar, 'unknown = aggregator-only'
from {{ ref('int_job_openings') }} group by lifecycle_status
union all
select 'baseline jobs / not in baseline', count_if(is_baseline)::varchar || ' / ' || count_if(not is_baseline)::varchar, 'not in baseline only after a second pull'
from {{ ref('int_job_openings') }}
union all
select 'new openings (employer-board jobs with an opening date)', count(opening_date)::varchar,
       'aggregator-only jobs never counted'
from {{ ref('int_job_openings') }}
union all
select 'ATS listings staging-inactive but not disappeared', count_if(source_type = 'ATS' and is_active = false and not is_disappeared)::varchar,
       'failed pulls or K > 1; 0 with K = 1 and no failed pull'
from {{ ref('int_job_listings') }}
union all
select 'pulls that failed', count_if(not is_successful)::varchar, 'each one explained'
from {{ ref('int_board_pulls') }}
union all
select 'sources fully pulled in week ' || week_start_date::varchar,
       count_if(is_full_pull)::varchar || ' of ' || count(*)::varchar || ': ' || listagg(iff(is_full_pull, source_name, null), ', '),
       'read period comparisons against this'
from {{ ref('int_source_weeks') }} group by week_start_date
union all
select 'jobs with a skill (full descriptions)',
       count(distinct s.job_sk)::varchar || ' of ' || (select count_if(description_basis = 'full') from {{ ref('int_job_openings') }})::varchar,
       'coverage for Q9'
from {{ ref('int_job_skills') }} s
join {{ ref('int_job_openings') }} o on o.job_sk = s.job_sk and o.description_basis = 'full'
