-- dbt/tests/assert_one_representative_per_job.sql
-- Every opening has exactly one representative listing. Returns the openings that do not.
select job_sk, count_if(is_representative) as representatives
from {{ ref('int_jobs_matched') }}
group by job_sk
having count_if(is_representative) <> 1