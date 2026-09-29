-- dbt/models/marts/dim_job_attributes.sql
--
-- Junk dimension (data_model.md, section 6): five short, low-cardinality attributes of a job,
-- one row per observed combination. The combination in which all four attributes are Unknown
-- (and so experience_level_basis is 'unknown') is the Unknown member ('-1').
-- job_category is in dim_role, with its role family.

with combinations as (
    select distinct
        employment_type,
        workplace_type,
        remote_status,
        experience_level,
        experience_level_basis
    from {{ ref('int_job_openings') }}
    where not (    employment_type  = 'Unknown'
               and workplace_type   = 'Unknown'
               and remote_status    = 'Unknown'
               and experience_level = 'Unknown')
)

select
    {{ dbt_utils.generate_surrogate_key(['employment_type', 'workplace_type', 'remote_status',
                                         'experience_level', 'experience_level_basis']) }} as job_attributes_sk,
    employment_type,
    workplace_type,
    remote_status,
    experience_level,
    experience_level_basis
from combinations

union all

select '-1', 'Unknown', 'Unknown', 'Unknown', 'Unknown', 'unknown'
