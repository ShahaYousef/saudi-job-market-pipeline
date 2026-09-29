-- models/staging/stg_workable_jobs.sql
--
-- Grain: one row per Workable posting per city (source_job_id + city_raw).
-- Workable returns one object per city for a role open in several cities, all sharing the
-- same shortcode, so the city is part of the identity. Latest snapshot wins.
--
-- v2 changes:
--   1. ingest_date from the landing path; ingested_at = that date at midnight UTC.
--   2. Dedup across snapshots on (shortcode, city) + first_seen_at / last_seen_at / is_active.
--   3. company_raw from the payload's own "name" field (e.g. "Qiddiya Investment Company")
--      instead of the file-name slug ("qiddiya-investment-company-1"). The slug is kept as board_slug.
--   4. apply_url from application_url (the real apply page), not shortlink.
--   5. full_description removed: the field does not exist in any Workable payload.
--      description is HTML; stripping happens in intermediate.
--   6. posting_date_raw: published_on / created_at are date-only, converted to midnight UTC.
--   7. Added department, function, industry, education.
--   8. copies_landed: how many landed copies of this posting RAW holds (all snapshots), counted
--      before dedup because this is the last layer where the copies exist. Summed into
--      fct_jobs.copies_landed and checked by tests/assert_raw_reconciles_with_staging.sql.

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
    from {{ source('raw', 'raw_workable') }}
),

flattened as (
    select
        file_name,
        loaded_at,
        ingest_date,
        board_latest_pull,
        raw_data:name::string as account_name,
        job.value             as job_json
    from source,
    lateral flatten(input => raw_data:jobs) as job
),

renamed as (
    select
        nullif(trim(job_json:shortcode::string), '')                                   as source_job_id,
        'workable'                                                                      as source_name,
        coalesce(
            nullif(trim(account_name), ''),
            nullif(trim(split_part(split_part(file_name, '/', -1), '.json', 1)), '')
        )                                                                               as company_raw,
        nullif(trim(job_json:title::string), '')                                        as title_raw,
        nullif(
            array_to_string(
                array_construct_compact(
                    nullif(trim(job_json:city::string), ''),
                    nullif(trim(job_json:state::string), ''),
                    nullif(trim(job_json:country::string), '')
                ),
                ', '
            ),
            ''
        )                                                                               as location_raw,
        nullif(trim(job_json:country::string), '')                                      as country_raw,
        nullif(trim(job_json:city::string), '')                                         as city_raw,
        nullif(trim(job_json:state::string), '')                                        as region_raw,  -- Workable's "state" holds the region, e.g. "Makkah Province"
        case
            when job_json:telecommuting::boolean = true then 'Remote'
            else null
        end                                                                              as workplace_type_raw,  -- false does not tell OnSite from Hybrid
        {{ normalize_employment_type('job_json:employment_type::string') }}              as employment_type,
        nullif(trim(job_json:description::string), '')                                  as description_plain,  -- HTML, stripped in intermediate
        nullif(trim(job_json:url::string), '')                                           as job_url,
        coalesce(
            nullif(trim(job_json:application_url::string), ''),
            nullif(trim(job_json:shortlink::string), '')
        )                                                                                as apply_url,
        {{ date_to_utc_timestamp('coalesce(job_json:published_on::date, job_json:created_at::date)') }}
                                                                                         as posting_date_raw,
        {{ date_to_utc_timestamp('ingest_date') }}                                       as ingested_at,

        -- source-specific
        nullif(trim(split_part(split_part(file_name, '/', -1), '.json', 1)), '')         as board_slug,
        job_json:telecommuting::boolean                                                  as telecommuting,
        nullif(trim(job_json:experience::string), '')                                    as experience,
        nullif(trim(job_json:department::string), '')                                    as department,
        nullif(trim(job_json:function::string), '')                                      as job_function,
        nullif(trim(job_json:industry::string), '')                                      as industry,
        nullif(trim(job_json:education::string), '')                                     as education,
        job_json:locations                                                               as locations_raw,

        -- lineage
        ingest_date,
        board_latest_pull,
        loaded_at,
        file_name
    from flattened
),

deduped as (
    select
        *,
        min(ingested_at) over (partition by source_job_id, city_raw) as first_seen_at,
        max(ingested_at) over (partition by source_job_id, city_raw) as last_seen_at,
        count(*)         over (partition by source_job_id, city_raw) as copies_landed,
        -- open when any copy of the posting sits in the latest pull of its own board. Comparing
        -- against the latest date of the whole source would mark every board that was not
        -- re-pulled as closed
        max(iff(ingest_date = board_latest_pull, 1, 0)) over (partition by source_job_id, city_raw) = 1 as is_active
    from renamed
    qualify row_number() over (
        partition by source_job_id, city_raw
        order by ingest_date desc, loaded_at desc, file_name
    ) = 1
)

select
    {{ dbt_utils.generate_surrogate_key(['source_name', 'source_job_id', 'city_raw']) }} as source_record_sk,
    * exclude (board_latest_pull)
from deduped