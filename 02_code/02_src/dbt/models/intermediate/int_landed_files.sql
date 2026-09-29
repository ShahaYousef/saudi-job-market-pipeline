-- dbt/models/intermediate/int_landed_files.sql
--
-- Grain: one row per landed file (ATS: one board file; aggregators: one API page envelope).
--
-- Why this model reads RAW directly: staging flattens files into postings, so a pull that returned
-- no posting, or failed, leaves no trace there. The pull calendar needs the landed files
-- themselves. Only file-level metadata is read here (file name, collection time, HTTP status,
-- whether the payload holds a job list); no posting field is used.
--
-- A file is successful when its payload is a job list:
--   ATS          the file holds a jobs array (Ashby, Workable, Greenhouse: raw_data:jobs;
--                SmartRecruiters: the file is itself an array). An empty array is a real
--                answer ("no open jobs"); an error body such as {"error": "Not Found"} is not.
--   Aggregators  the page returned HTTP 200 with a parseable body.
-- Feeds int_board_pulls (pull calendar) and int_source_weeks (weekly coverage).

{% set ats = [
    ('ashby',           'raw_ashby',           "is_array(raw_data:jobs)",  "array_size(raw_data:jobs)"),
    ('workable',        'raw_workable',        "is_array(raw_data:jobs)",  "array_size(raw_data:jobs)"),
    ('greenhouse',      'raw_greenhouse',      "is_array(raw_data:jobs)",  "array_size(raw_data:jobs)"),
    ('smartrecruiters', 'raw_smartrecruiters', "is_array(raw_data)",       "array_size(raw_data)"),
] %}

with ats_files as (
    {% for source_name, table, ok_expr, size_expr in ats %}
    select
        file_name,
        '{{ source_name }}'                         as source_name,
        {{ board_from_path('file_name') }}          as board,
        {{ ingest_date_from_path('file_name') }}    as pull_date,
        null::string                                as query_label,
        coalesce({{ ok_expr }}, false)              as is_successful_file,
        iff({{ ok_expr }}, {{ size_expr }}, 0)      as postings_in_file
    from {{ source('raw', table) }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

aggregator_pages as (
    {% for source_name, list_key in [('jooble', 'jobs'), ('jsearch', 'data')] %}
    select
        file_name,
        '{{ source_name }}'                                                            as source_name,
        '{{ source_name }}'                                                            as board,
        convert_timezone('{{ var("business_timezone") }}',
                         raw_data:ingested_at::timestamp_tz)::date                    as pull_date,
        -- batch_id is <source>__<query label>__<timestamp>: the label names the query of the matrix
        split_part(raw_data:batch_id::string, '__', 2)                                 as query_label,
        coalesce(raw_data:http_status::number = 200
                 and try_parse_json(raw_data:response_raw::string) is not null, false)  as is_successful_file,
        coalesce(iff(raw_data:http_status::number = 200,
                     array_size(try_parse_json(raw_data:response_raw::string):{{ list_key }}), 0), 0) as postings_in_file
    from {{ source('raw', 'raw_' ~ source_name) }}
    {% if not loop.last %}union all{% endif %}
    {% endfor %}
),

files as (
    select * from ats_files
    union all
    select * from aggregator_pages
)

select
    file_name,
    source_name,
    board,
    pull_date,
    {{ week_start('pull_date') }}                                  as week_start_date,
    query_label,
    is_successful_file,
    postings_in_file
from files
