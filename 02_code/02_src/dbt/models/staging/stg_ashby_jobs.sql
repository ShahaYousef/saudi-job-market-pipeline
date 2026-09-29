
-- models/staging/stg_ashby_jobs.sql
--
-- Grain: one row per Ashby posting (source_job_id). When the same posting appears in
-- several ingest_date snapshots, the latest snapshot wins.
--
-- v2 changes:
--   1. ingest_date read from the landing path; ingested_at = that date at midnight UTC.
--      (loaded_at is TIMESTAMP_NTZ in the session time zone and is the load time, not the
--      collection time, so it is kept only as a tie-breaker.)
--   2. Within-source dedup across snapshots + first_seen_at / last_seen_at / is_active.
--   3. Geographic scope enforced here on the structured country field. The extraction
--      keyword filter let a "Thailand (Remote)" posting through ("hail" is inside "Thailand").
--   4. posting_date_raw converted to UTC.
--   5. secondary_locations_raw kept.

with source as (
    select
        raw_data,
        file_name,
        loaded_at,
        {{ ingest_date_from_path('file_name') }} as ingest_date,
        -- latest pull of the board this file belongs to. Taken from the landed files, before they
        -- are flattened into jobs, so a board whose latest pull returned no jobs still counts as
        -- pulled on that date and its old postings are correctly closed
        max({{ ingest_date_from_path('file_name') }}) over (
            partition by {{ board_from_path('file_name') }}
        ) as board_latest_pull
    from {{ source('raw', 'raw_ashby') }}
),

flattened as (
    select
        file_name,
        loaded_at,
        ingest_date,
        board_latest_pull,
        job.value as job_json
    from source,
    lateral flatten(input => raw_data:jobs) as job
),

renamed as (
    select
        nullif(trim(job_json:id::string), '')                                         as source_job_id,
        'ashby'                                                                        as source_name,
        nullif(trim(split_part(split_part(file_name, '/', -1), '.json', 1)), '')       as company_raw,
        nullif(trim(job_json:title::string), '')                                       as title_raw,
        nullif(trim(job_json:location::string), '')                                    as location_raw,
        nullif(trim(job_json:address.postalAddress.addressCountry::string), '')        as country_raw,
        nullif(trim(job_json:address.postalAddress.addressLocality::string), '')       as city_raw,
        nullif(trim(job_json:address.postalAddress.addressRegion::string), '')         as region_raw,
        nullif(trim(job_json:workplaceType::string), '')                               as workplace_type_raw,
        {{ normalize_employment_type('job_json:employmentType::string') }}              as employment_type,
        nullif(trim(job_json:descriptionPlain::string), '')                            as description_plain,
        nullif(trim(job_json:jobUrl::string), '')                                      as job_url,
        nullif(trim(job_json:applyUrl::string), '')                                    as apply_url,
        convert_timezone('UTC', job_json:publishedAt::timestamp_tz)                    as posting_date_raw,
        {{ date_to_utc_timestamp('ingest_date') }}                                     as ingested_at,

        -- source-specific
        nullif(trim(job_json:department::string), '')                                  as department,
        nullif(trim(job_json:team::string), '')                                        as team,
        job_json:isRemote::boolean                                                     as is_remote,
        job_json:secondaryLocations                                                    as secondary_locations_raw,

        -- lineage
        ingest_date,
        board_latest_pull,
        loaded_at,
        file_name
    from flattened
),

scoped as (
    select *
    from renamed
    where country_raw = 'Saudi Arabia'
       -- fallback only when the structured field is missing (the keyword filter at extraction
       -- let "Thailand (Remote)" through because "hail" is inside "Thailand")
       or (country_raw is null
           and location_raw ilike any ('%saudi%', '%riyadh%', '%jeddah%', '%dammam%', '%khobar%', '%dhahran%'))
),

deduped as (
    select
        *,
        -- observation window over every snapshot, computed before QUALIFY drops the older copies
        min(ingested_at) over (partition by source_job_id) as first_seen_at,
        max(ingested_at) over (partition by source_job_id) as last_seen_at,
        count(*)         over (partition by source_job_id) as copies_landed,
        -- open when any copy of the posting sits in the latest pull of its own board. Comparing
        -- against the latest date of the whole source would mark every board that was not
        -- re-pulled as closed
        max(iff(ingest_date = board_latest_pull, 1, 0)) over (partition by source_job_id) = 1 as is_active
    from scoped
    qualify row_number() over (
        partition by source_job_id
        order by ingest_date desc, loaded_at desc, file_name
    ) = 1
)

select
    {{ dbt_utils.generate_surrogate_key(['source_name', 'source_job_id']) }} as source_record_sk,
    * exclude (board_latest_pull)
from deduped