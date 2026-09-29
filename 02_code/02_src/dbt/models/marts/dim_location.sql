-- dbt/models/marts/dim_location.sql
--
-- One row per location used by an opening, at the most precise level the source gave:
-- city, region, or Saudi Arabia as a whole (country). Hierarchy: country -> region -> city.
-- Plus the Unknown member ('-1'), kept for referential completeness.
-- city = 'Unknown' on a region or country row means "no city given"; use location_label in reports.

with locations as (
    select distinct
        coalesce(city_std, 'Unknown')   as city,
        coalesce(region_std, 'Unknown') as region,
        location_level
    from {{ ref('int_job_openings') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['city', 'region', 'location_level']) }} as location_sk,
    city,
    region,
    'SA'                                                                         as country,
    location_level,
    -- display name for reports: a country- or region-level row is not a missing city
    case location_level
        when 'city'   then city
        when 'region' then region || ' (no city given)'
        else 'Saudi Arabia (no city given)'
    end                                                                          as location_label
from locations

union all

select '-1', 'Unknown', 'Unknown', 'Unknown', 'unknown', 'Unknown'