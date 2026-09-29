-- dbt/models/marts/dim_source.sql
--
-- One row per source, from seed_sources. No Unknown member: every job has a representative
-- listing, and every listing comes from a known source.
-- The fact joins it through primary_source_sk (the source of the representative listing).

select
    {{ dbt_utils.generate_surrogate_key(['source_name']) }} as source_sk,
    source_name,
    source_type,
    collection_method,
    source_priority
from {{ ref('seed_sources') }}
