-- dbt/analyses/business_questions.sql
--
-- Answers to Q1 to Q9 (data_model.md, section 2), read from the MARTS schema only.
-- Run each query on its own in a Snowflake worksheet (cursor inside it, then Ctrl+Enter).
--
-- Time frames:
--   Observation period (Q1 to Q6, Q9): every row of fct_jobs. A job is in the dataset because it
--     was seen at least once between the first and the latest successful pull, so its open
--     interval overlaps the period.
--   Week of an event (Q7, Q8): the date role of the event joined to dim_date.week_start_date.
-- Jobs = SUM(job_count). Weekly answers are read against collection coverage
-- (INTERMEDIATE.INT_SOURCE_WEEKS): a source not fully pulled in a week looks like a drop.

use schema job_pipeline_db.marts;

-- Q1. How many unique job openings were open in Saudi Arabia during the observation period?
select sum(f.job_count)             as job_openings,
       count(distinct f.posting_sk) as job_postings,
       sum(f.listing_count)         as listings
from fct_jobs f;


-- Q2. Which regions had the most open job openings during the observation period?
-- City is the drill-down. Country-level jobs (no region given) are shown on their own row.
select iff(l.location_level = 'country', 'Saudi Arabia (no region given)', l.region) as region,
       sum(f.job_count)                                                          as job_openings
from fct_jobs f
join dim_location l on f.location_sk = l.location_sk
group by 1
order by job_openings desc;

-- Q2, drill-down: the 10 cities with the most open job openings (a tie at rank 10 keeps both)
select l.city, l.region, sum(f.job_count) as job_openings
from fct_jobs f
join dim_location l on f.location_sk = l.location_sk
where l.location_level = 'city'
group by l.city, l.region
qualify rank() over (order by sum(f.job_count) desc) <= 10
order by job_openings desc, l.city;


-- Q3. Which employers had the most open job openings during the observation period,
-- excluding undisclosed employers and recruitment agencies? A tie at rank 10 keeps both.
select c.company_name, sum(f.job_count) as job_openings
from fct_jobs f
join dim_company c on f.company_sk = c.company_sk
where c.company_sk <> '-1'
  and not c.is_recruitment_agency
group by c.company_sk, c.company_name
qualify rank() over (order by sum(f.job_count) desc) <= 10
order by job_openings desc, c.company_name;


-- Q4. Which role families had the most open job openings during the observation period?
-- Job category is the drill-down; the share in Other is part of the answer.
select r.role_family,
       r.job_category,
       sum(f.job_count)                                                         as job_openings,
       round(100 * sum(f.job_count) / sum(sum(f.job_count)) over (), 1)         as pct_of_jobs,
       sum(sum(f.job_count)) over (partition by r.role_family)                  as family_openings
from fct_jobs f
join dim_role r on f.role_sk = r.role_sk
group by r.role_family, r.job_category
order by family_openings desc, job_openings desc;


-- Q5. What share of open job openings during the observation period falls into each
-- employment type? The base is jobs with a known type; the known share is shown with it.
select a.employment_type,
       sum(f.job_count)                                                         as job_openings,
       round(100 * sum(f.job_count) / sum(sum(f.job_count)) over (), 1)         as pct_of_known,
       round(100 * sum(sum(f.job_count)) over ()
                 / (select sum(job_count) from fct_jobs), 1)                    as known_share_of_all_jobs
from fct_jobs f
join dim_job_attributes a on f.job_attributes_sk = a.job_attributes_sk
where a.employment_type <> 'Unknown'
group by a.employment_type
order by job_openings desc;


-- Q6. Which experience levels are most requested in each region during the observation period?
-- Only levels stated by the source are counted (experience_level_basis = 'source'). The title
-- rules can return Internship, Mid-Senior or Director only (seed_seniority_keywords), never Entry
-- or Associate, so mixing them in would push every region toward Mid-Senior. Stated levels come
-- from the Workable and SmartRecruiters boards, so the answer describes the employers on those
-- boards, not the whole market. Regions with fewer than 20 such jobs are left out.
with counted as (
    select l.region,
           a.experience_level,
           sum(f.job_count)                                                     as job_openings
    from fct_jobs f
    join dim_location l       on f.location_sk = l.location_sk
    join dim_job_attributes a on f.job_attributes_sk = a.job_attributes_sk
    where l.region <> 'Unknown'
      and a.experience_level_basis = 'source'
    group by l.region, a.experience_level
)
select region,
       experience_level,
       job_openings,
       round(100 * job_openings / sum(job_openings) over (partition by region), 1) as pct_of_region,
       sum(job_openings) over (partition by region)                             as jobs_with_stated_level
from counted
qualify sum(job_openings) over (partition by region) >= 20
order by jobs_with_stated_level desc, job_openings desc;


-- Q7. How many new job openings appeared in each week?
-- A new opening is an employer-board job not seen in any baseline pull (opening_date_sk <> -1).
select d.week_start_date, sum(f.job_count) as new_openings
from fct_jobs f
join dim_date d on f.opening_date_sk = d.date_sk
where f.opening_date_sk <> -1
group by d.week_start_date
order by d.week_start_date;


-- Q8. For job openings that disappeared in each week, what was the median number of days they
-- were listed? Employer-board jobs only (lifecycle_status = 'disappeared').
select d.week_start_date,
       sum(f.job_count)                         as disappeared_jobs,
       median(f.days_listed)                    as median_days_listed,
       count_if(f.days_listed_basis = 'posted') as from_posting_date
from fct_jobs f
join dim_date d on f.disappeared_date_sk = d.date_sk
where f.lifecycle_status = 'disappeared'
group by d.week_start_date
order by d.week_start_date;


-- Q9. Which skills are mentioned by the largest share of open job openings that have a full
-- description, during the observation period? Jobs whose posting is a Jooble snippet, or has no
-- description, are outside the base. A tie at rank 20 keeps both.
-- Jobs are counted as COUNT(DISTINCT job_sk) because the bridge has one row per job per skill.
with full_jobs as (
    select f.job_sk
    from fct_jobs f
    join dim_job_posting p on f.posting_sk = p.posting_sk
    where p.description_basis = 'full'
)
select s.skill_name,
       s.skill_group,
       count(distinct b.job_sk)                                                 as job_openings,
       round(100 * count(distinct b.job_sk) / (select count(*) from full_jobs), 1) as pct_of_full_description_jobs
from bridge_job_skill b
join full_jobs j on b.job_sk = j.job_sk
join dim_skill s on b.skill_sk = s.skill_sk
group by s.skill_name, s.skill_group
qualify rank() over (order by count(distinct b.job_sk) desc) <= 20
order by job_openings desc, s.skill_name;
