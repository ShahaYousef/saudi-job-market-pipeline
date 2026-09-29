-- dbt/models/marts/dim_role.sql
--
-- What role (data_model.md, section 6). Two-level hierarchy: role_family -> job_category.
-- One row per job category of seed_role_families (the 18 categories of seed_job_categories plus
-- Other), and the Unknown member ('-1') for a title with no matching key (job_category Unknown).
-- Built from the seed, not from the jobs, so a category with no job this run still has its row.

select
    {{ dbt_utils.generate_surrogate_key(['job_category']) }}  as role_sk,
    job_category,
    role_family
from {{ ref('seed_role_families') }}

union all

select '-1', 'Unknown', 'Unknown'
