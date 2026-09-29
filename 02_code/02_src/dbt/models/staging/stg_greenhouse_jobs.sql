-- models/staging/stg_greenhouse_jobs.sql
--
-- Grain: one row per Greenhouse posting (source_job_id). Latest snapshot wins.
--
-- v2 changes:
--   1. ingest_date from the landing path; ingested_at = that date at midnight UTC.
--   2. Dedup across snapshots and across boards. Umbrella boards (e.g. cssmerge) can list the
--      same posting as a brand's own board (pronto, kitchenpark, namaa), under the same id.
--   3. Metadata (Employment Type, Brand) extracted per file + job, aggregated to one row.
--      The v1 LEFT JOIN on job id alone would fan out once a second snapshot is loaded.
--   4. company_raw: "Careers page" suffix removed ("ATOMS Careers page" -> "ATOMS").
--      Brand from metadata kept separately as brand_raw; which one wins is decided in intermediate.
--   5. Timestamps converted to UTC. Greenhouse returns local offsets (-04:00), not UTC.
--   6. is_active per board, not per source: a posting is active when any copy of it sits in the
--      latest pull of its own board. Boards not re-pulled keep their postings open.
--   7. Geographic scope enforced here. Greenhouse has no structured country field, so the Saudi
--      keywords of the extraction script are matched against the location text. The files landed
--      on 2026-09-09 were not filtered at extraction and carried postings in Dubai, Cairo and other
--      non-Saudi cities; without this filter they looked like "closed" postings once the filtered
--      2026-09-24 pull no longer listed them.
--   8. board_slug read with board_from_path(), so "hala.json" and "hala_jobs.json" are one board.

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
    from {{ source('raw', 'raw_greenhouse') }}
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

metadata_extracted as (
    select
        f.file_name,
        f.job_json:id::string as job_id,
        max(case when meta.value:name::string = 'Employment Type' then meta.value:value::string end) as employment_type_value,
        max(case when meta.value:name::string = 'Brand'           then meta.value:value::string end) as brand_value
    from flattened f,
    lateral flatten(input => f.job_json:metadata, outer => true) as meta
    group by 1, 2
),

renamed as (
    select
        nullif(trim(f.job_json:id::string), '')                                        as source_job_id,
        'greenhouse'                                                                    as source_name,
        nullif(trim(regexp_replace(f.job_json:company_name::string,
                                   '\\s*careers\\s*page\\s*$', '', 1, 1, 'i')), '')      as company_raw,
        nullif(trim(f.job_json:title::string), '')                                      as title_raw,
        nullif(trim(f.job_json:location.name::string), '')                              as location_raw,
        null::string                                                                    as country_raw,   -- one flat location string only
        null::string                                                                    as city_raw,
        null::string                                                                    as region_raw,
        null::string                                                                    as workplace_type_raw,  -- no remote/onsite signal in the payload
        {{ normalize_employment_type('m.employment_type_value') }}                       as employment_type,
        -- HTML with escaped entities (&lt;p&gt;), decoded and stripped in intermediate
        nullif(trim(f.job_json:content::string), '')                                    as description_plain,
        nullif(trim(f.job_json:absolute_url::string), '')                               as job_url,
        nullif(trim(f.job_json:absolute_url::string), '')                               as apply_url,
        convert_timezone('UTC', f.job_json:first_published::timestamp_tz)               as posting_date_raw,
        {{ date_to_utc_timestamp('f.ingest_date') }}                                    as ingested_at,

        -- source-specific
        {{ board_from_path('f.file_name') }}                                            as board_slug,
        nullif(trim(m.brand_value), '')                                                 as brand_raw,
        convert_timezone('UTC', f.job_json:updated_at::timestamp_tz)                    as updated_at_raw,
        nullif(trim(f.job_json:requisition_id::string), '')                             as requisition_id,
        nullif(trim(f.job_json:departments[0].name::string), '')                        as department,
        nullif(trim(f.job_json:offices[0].name::string), '')                            as office_name,

        -- lineage
        f.ingest_date,
        f.board_latest_pull,
        f.loaded_at,
        f.file_name
    from flattened f
    left join metadata_extracted m
        on  f.file_name          = m.file_name
        and f.job_json:id::string = m.job_id
),

scoped as (
    -- same keyword list as pipeline/ingestion/greenhouse/greenhouse.py; applied before dedup so
    -- first_seen_at / last_seen_at / is_active are computed over in-scope copies only
    select *
    from renamed
    where location_raw ilike any (
        '%saudi%', '%ksa%', '%riyadh%', '%jeddah%', '%dammam%', '%khobar%', '%dhahran%',
        '%jubail%', '%mecca%', '%makkah%', '%medina%', '%madinah%', '%jazan%', '%jizan%',
        '%tabuk%', '%abha%', '%taif%', '%yanbu%', '%al ahsa%', '%hofuf%', '%neom%',
        '%king abdullah economic city%', '%eastern province%', '%western province%'
    )
),

deduped as (
    select
        *,
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