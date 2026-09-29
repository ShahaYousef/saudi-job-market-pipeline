-- dbt/models/marts/bridge_job_skill.sql
--
-- Grain: one row per job per skill (data_model.md, section 7.2), from int_job_skills: a skill
-- keyword matched as a whole word in the titles and cleaned descriptions of every listing of the
-- job. matched_in is 'title' when any listing's title names the skill, else 'description'.
--
-- A job with three skills has three rows here, so count jobs as COUNT(DISTINCT job_sk) whenever
-- this bridge is in the filter path. Skill shares use jobs with a full description as the
-- denominator (fct_jobs -> dim_job_posting.description_basis = 'full').

select
    job_sk,
    {{ dbt_utils.generate_surrogate_key(['skill_name']) }}  as skill_sk,
    matched_in
from {{ ref('int_job_skills') }}
