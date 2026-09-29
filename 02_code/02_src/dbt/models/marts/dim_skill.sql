-- dbt/models/marts/dim_skill.sql
--
-- Which skills (data_model.md, section 6). One row per canonical skill of seed_skills (several
-- keywords can name one skill), plus the Unknown member ('-1'). Reached from fct_jobs through
-- bridge_job_skill.

select distinct
    {{ dbt_utils.generate_surrogate_key(['skill_name']) }}  as skill_sk,
    skill_name,
    skill_group
from {{ ref('seed_skills') }}

union all

select '-1', 'Unknown', 'Unknown'
