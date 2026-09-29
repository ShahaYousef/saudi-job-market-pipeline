-- models/staging/stg_jooble_jobs.sql
--
-- Grain: one row per Jooble posting (source_job_id).
--
-- Built on the team version, with five changes specific to how this source was collected:
--
--   1. Only HTTP 200 pages are parsed. Failed pages are landed on purpose in the raw
--      layer and carry no usable payload.
--
--   2. try_parse_json instead of parse_json, so a truncated or malformed body yields
--      null instead of aborting the whole run.
--
--   3. ingested_at is the collection time recorded in the envelope, not loaded_at.
--      Every page loaded by one COPY INTO shares one loaded_at value, while each page carries
--      its own collection time. loaded_at therefore cannot order duplicate copies; it is kept
--      only as a tie-breaker, followed by the file name and the position in the page, so the
--      same copy is kept on every build.
--
--   4. Within-source duplicates are removed here. Coverage was built from overlapping
--      queries against a source that caps each query at 1000 records, so the same
--      posting came back under the same id many times: 32,297 rows for 12,828 ids in the
--      final build (analyses/pipeline_audit.sql).
--      Keeping them would fail a unique test on source_job_id, this model's key.
--      The same real job listed on a different source carries a different id, passes
--      that test, and is resolved in the intermediate layer instead.
--
--   5. copies_landed: how many landed copies of this posting RAW holds, counted before dedup.

with source as (
    select raw_data, file_name, loaded_at
    from {{ source('raw', 'raw_jooble') }}
),

parsed as (
    select
        file_name,
        loaded_at,
        raw_data:batch_id::string                      as batch_id,
        raw_data:ingested_at::timestamp_tz             as ingested_at,
        raw_data:http_status::number                   as http_status,
        try_parse_json(raw_data:response_raw::string)  as response_json
    from source
    where raw_data:http_status::number = 200
),

flattened as (
    select
        file_name,
        loaded_at,
        batch_id,
        ingested_at,
        http_status,
        job.index as job_index,
        job.value as job_json
    from parsed,
    -- note: Jooble's array key is "jobs", not "data" like JSearch
    lateral flatten(input => response_json:jobs) as job
),

keyed as (
    -- the key is extracted in its own step so the window functions below can partition on it
    select
        flattened.*,
        nullif(trim(job_json:id::string), '') as source_job_id
    from flattened
),

deduped as (

select
    -- shared / common columns (same names, same order as the other staging models)
    source_job_id,
    'jooble'                                                                       as source_name,
    nullif(trim(job_json:company::string), '')                                     as company_raw,
    nullif(trim(job_json:title::string), '')                                       as title_raw,
    nullif(trim(job_json:location::string), '')                                    as location_raw,
    null::string                                                                   as country_raw,         -- Jooble gives no structured breakdown, only the flat location string
    null::string                                                                   as city_raw,
    null::string                                                                   as region_raw,
    null::string                                                                   as workplace_type_raw,  -- Jooble gives no remote/onsite signal at all
    null::string                                                                   as employment_type,     -- "type" was an empty string in every sample seen, treated as no signal
    nullif(trim(job_json:snippet::string), '')                                     as description_plain,   -- a short snippet, not the full description
    nullif(trim(job_json:link::string), '')                                        as job_url,
    nullif(trim(job_json:link::string), '')                                        as apply_url,
    null::timestamp_tz                                                             as posting_date_raw,    -- deliberately null, "updated" is a crawl timestamp, not a publish date

    ingested_at,                                                                                           -- true collection time of the surviving copy

    -- source-specific columns (unique to Jooble, handled at intermediate stage)
    nullif(trim(job_json:source::string), '')                                      as underlying_source,   -- e.g. "teamtailor.com", same role as JSearch's job_publisher
    nullif(trim(job_json:salary::string), '')                                      as salary_raw,
    job_json:updated::timestamp_tz                                                 as crawled_at,          -- kept for reference only, explicitly NOT used as posting_date_raw

    -- observation window across every landed copy, computed before the copies are dropped
    -- because this is the last layer where they still exist
    min(ingested_at) over (partition by source_job_id)                             as first_seen_at,
    max(ingested_at) over (partition by source_job_id)                             as last_seen_at,
    count(*)         over (partition by source_job_id)                             as copies_landed,

    batch_id,
    http_status

from keyed

-- keep the most recently collected copy of each posting
qualify row_number() over (
    partition by source_job_id
    order by ingested_at desc, loaded_at desc, file_name desc, job_index
) = 1

)

select
    -- surrogate key: unique across all six sources, because the same raw id can occur in more than one source
    {{ dbt_utils.generate_surrogate_key(['source_name', 'source_job_id']) }} as source_record_sk,
    *
from deduped