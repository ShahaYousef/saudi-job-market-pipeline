-- dbt/tests/assert_job_lifecycle_consistent.sql
-- Lifecycle rules of data_model.md, section 7.1. Every returned row breaks one of them:
--   1. a job is open at least on its first day;
--   2. disappeared_date is set exactly when the job disappeared;
--   3. a job disappears after its last sighting on an employer board (an aggregator copy can
--      outlive the employer's own posting, so aggregator sightings are not compared);
--   4. a baseline job or an aggregator-only job is never new, and every other job has an
--      opening date;
--   5. no job is open beyond the latest successful pull.
select job_sk, lifecycle_status, first_seen_date, open_until_date, disappeared_date, opening_date, is_baseline
from {{ ref('int_job_openings') }}
where open_until_date < first_seen_date
   or (lifecycle_status = 'disappeared') <> (disappeared_date is not null)
   or disappeared_date <= ats_last_seen_date
   or ((is_baseline or lifecycle_status = 'unknown') and opening_date is not null)
   or (not is_baseline and lifecycle_status <> 'unknown' and opening_date is null)
   or open_until_date > as_of_date
