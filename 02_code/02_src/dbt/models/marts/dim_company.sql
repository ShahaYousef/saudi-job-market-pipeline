-- dbt/models/marts/dim_company.sql
--
-- One row per company (company_norm), plus the Unknown member ('-1') for missing names and
-- placeholders such as "Private Company".
--   company_name           the name of the company's highest-priority listing (the standard
--                          name from seed_company_aliases when the company is listed there)
--   is_recruitment_agency  from seed_company_aliases
--   industry               most frequent value across the company's listings (Workable and
--                          SmartRecruiters only); ties go to the higher-priority source

with listings as (
    select * from {{ ref('int_jobs_matched') }}
    where company_norm is not null
),

names as (
    select
        company_norm,
        company_name,
        is_recruitment_agency
    from listings
    qualify row_number() over (
        partition by company_norm
        order by source_priority, first_seen_at, source_record_sk
    ) = 1
),

industries as (
    select company_norm, industry
    from listings
    where industry is not null
    group by company_norm, industry
    qualify row_number() over (
        partition by company_norm
        order by count(*) desc, min(source_priority), industry
    ) = 1
)

select
    {{ dbt_utils.generate_surrogate_key(['n.company_norm']) }} as company_sk,
    n.company_name,
    n.company_norm,
    i.industry,
    n.is_recruitment_agency
from names n
left join industries i
    on n.company_norm = i.company_norm

union all

select '-1', 'Employer not disclosed', null, null, false