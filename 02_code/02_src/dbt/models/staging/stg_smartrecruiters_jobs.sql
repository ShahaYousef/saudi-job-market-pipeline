-- models/staging/stg_smartrecruiters_jobs.sql
--
-- Grain: one row per SmartRecruiters posting (source_job_id). Latest snapshot wins.
--
-- v2 changes:
--   1. ingest_date from the landing path; ingested_at = that date at midnight UTC.
--   2. Dedup across snapshots + first_seen_at / last_seen_at / is_active.
--   3. job_url / apply_url: "ref" is an API endpoint (api.smartrecruiters.com/v1/...),
--      not a page a person can open. The public posting URL is built from
--      company.identifier + id. The API ref is kept as api_ref_url.
--   4. location_raw: empty parts removed ("Riyadh, , Saudi Arabia" -> "Riyadh, Saudi Arabia").
--   5. country_raw upper-cased ("sa" -> "SA").
--   6. posting_date_raw converted to UTC. Added department_label, latitude, longitude.

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
    from {{ source('raw', 'raw_smartrecruiters') }}
),

flattened as (
    select
        file_name,
        loaded_at,
        ingest_date,
        board_latest_pull,
        job.value as job_json
    from source,
    -- raw_data IS the array itself (no "jobs"/"data" wrapper key)
    lateral flatten(input => raw_data) as job
),

renamed as (
    select
        nullif(trim(job_json:id::string), '')                                          as source_job_id,
        'smartrecruiters'                                                               as source_name,
        nullif(trim(job_json:company.name::string), '')                                 as company_raw,
        nullif(trim(job_json:name::string), '')                                         as title_raw,
        nullif(trim(regexp_replace(job_json:location.fullLocation::string,
                                   '(\\s*,\\s*)+', ', '), ', '), '')                     as location_raw,
        nullif(upper(trim(job_json:location.country::string)), '')                      as country_raw,
        nullif(trim(job_json:location.city::string), '')                                as city_raw,
        nullif(trim(job_json:location.region::string), '')                              as region_raw,
        -- the only source with separate remote and hybrid flags, so all three states are distinguishable
        case
            when job_json:location.remote::boolean = true  then 'Remote'
            when job_json:location.hybrid::boolean = true  then 'Hybrid'
            when job_json:location.remote::boolean = false
             and job_json:location.hybrid::boolean = false then 'OnSite'
            else null
        end                                                                              as workplace_type_raw,
        {{ normalize_employment_type('job_json:typeOfEmployment.label::string') }}        as employment_type,
        nullif(trim(job_json:jobAd.sections.jobDescription.text::string), '')            as description_plain,  -- HTML, stripped in intermediate
        'https://jobs.smartrecruiters.com/'
            || job_json:company.identifier::string || '/' || job_json:id::string         as job_url,
        'https://jobs.smartrecruiters.com/'
            || job_json:company.identifier::string || '/' || job_json:id::string         as apply_url,
        convert_timezone('UTC', job_json:releasedDate::timestamp_tz)                     as posting_date_raw,
        {{ date_to_utc_timestamp('ingest_date') }}                                       as ingested_at,

        -- source-specific
        nullif(trim(job_json:company.identifier::string), '')                            as board_slug,
        nullif(trim(job_json:ref::string), '')                                           as api_ref_url,
        nullif(trim(job_json:refNumber::string), '')                                     as requisition_ref,
        nullif(trim(job_json:industry.label::string), '')                                as industry_label,
        nullif(trim(job_json:function.label::string), '')                                as function_label,
        nullif(trim(job_json:department.label::string), '')                              as department_label,
        nullif(trim(job_json:experienceLevel.label::string), '')                         as experience_level,
        nullif(trim(job_json:visibility::string), '')                                    as visibility,
        nullif(trim(job_json:language.code::string), '')                                 as language_code,
        try_to_double(job_json:location.latitude::string)                                as latitude,
        try_to_double(job_json:location.longitude::string)                               as longitude,
        nullif(trim(job_json:jobAd.sections.companyDescription.text::string), '')        as company_description_raw,
        nullif(trim(job_json:jobAd.sections.qualifications.text::string), '')            as qualifications_raw,
        nullif(trim(job_json:jobAd.sections.additionalInformation.text::string), '')     as additional_information_raw,
        job_json:customField                                                             as custom_fields_raw,

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
        min(ingested_at) over (partition by source_job_id) as first_seen_at,
        max(ingested_at) over (partition by source_job_id) as last_seen_at,
        count(*)         over (partition by source_job_id) as copies_landed,

        -- open when any copy of the posting sits in the latest pull of its own board. Comparing
        -- against the latest date of the whole source would mark every board that was not
        -- re-pulled as closed
        max(iff(ingest_date = board_latest_pull, 1, 0)) over (partition by source_job_id) = 1 as is_active
    from renamed
    qualify row_number() over (
        partition by source_job_id
        order by ingest_date desc, loaded_at desc, file_name
    ) = 1
)

select
    {{ dbt_utils.generate_surrogate_key(['source_name', 'source_job_id']) }} as source_record_sk,
    * exclude (board_latest_pull)
from deduped