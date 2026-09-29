-- dbt/tests/assert_fuzzy_merges_keep_level_words.sql
-- A fuzzy merge must never join titles with different level words (data_model.md, section 8.4):
-- "data analyst" and "data analyst intern" are two jobs. Every returned row is a job whose
-- listings carry more than one level signature (= failure).
select job_sk, count(distinct {{ level_signature('title_norm') }}) as signatures
from {{ ref('int_jobs_matched') }}
where match_tier = 'fuzzy'
  and title_norm is not null
group by job_sk
having count(distinct {{ level_signature('title_norm') }}) > 1
