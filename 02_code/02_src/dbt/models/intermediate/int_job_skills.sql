-- dbt/models/intermediate/int_job_skills.sql
--
-- Grain: one row per job per skill (data_model.md, sections 6 and 7.2).
--
-- Skills come from seed_skills, matched as whole words against the normalized title and the
-- cleaned description of every listing of the job, not only the representative one: a job's
-- aggregator copy can name a tool its employer page leaves out, and the reverse.
--
-- A Jooble description is a snippet of about 280 characters, so a job found on Jooble alone
-- shows fewer skills because its text is short, not because it asks for fewer. Skill shares use
-- jobs whose description_basis is 'full' (int_job_openings) as the denominator.

with listings as (
    select
        job_sk,
        source_record_sk,
        title_norm,
        {{ normalize_text('description_text') }}   as description_norm
    from {{ ref('int_jobs_matched') }}
),

hits as (
    select
        l.job_sk,
        l.source_record_sk,
        k.skill_name,
        k.skill_group,
        coalesce(' ' || l.title_norm || ' ' like '% ' || k.keyword || ' %', false)        as in_title,
        coalesce(' ' || l.description_norm || ' ' like '% ' || k.keyword || ' %', false)  as in_description
    from listings l
    join {{ ref('seed_skills') }} k
        on ' ' || l.title_norm || ' '       like '% ' || k.keyword || ' %'
        or ' ' || l.description_norm || ' ' like '% ' || k.keyword || ' %'
)

select
    {{ dbt_utils.generate_surrogate_key(['job_sk', 'skill_name']) }}   as job_skill_sk,
    job_sk,
    skill_name,
    skill_group,
    iff(boolor_agg(in_title), 'title', 'description')                   as matched_in,
    count(distinct source_record_sk)                                    as listings_matched
from hits
group by job_sk, skill_name, skill_group
