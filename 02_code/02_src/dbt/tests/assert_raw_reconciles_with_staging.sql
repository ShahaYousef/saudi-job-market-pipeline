-- dbt/tests/assert_raw_reconciles_with_staging.sql
-- RAW -> staging row-count reconciliation (data_model.md, section 10.4, automated).
--
--   raw_rows       job objects landed in RAW, counted the same way staging reads them
--                  (Jooble / JSearch: HTTP 200 pages only, which is the only payload that exists)
--   staged_copies  SUM(copies_landed) in staging = every landed copy that staging kept before its
--                  within-source dedup
--
-- Rules:
--   1. No source may stage more copies than RAW holds.
--   2. Sources with no scope filter in staging (workable, smartrecruiters, jooble, jsearch) must
--      account for every RAW row: raw_rows = staged_copies.
--   3. ashby and greenhouse drop out-of-scope (non-Saudi) rows in staging, so for them
--      raw_rows - staged_copies is the out-of-scope count, reported by analyses/pipeline_audit.sql.
-- Every returned row is a failure.
 
with raw_counts as (
 
    select 'ashby' as source_name, count(*) as raw_rows
    from {{ source('raw', 'raw_ashby') }},
         lateral flatten(input => raw_data:jobs)
 
    union all
    select 'greenhouse', count(*)
    from {{ source('raw', 'raw_greenhouse') }},
         lateral flatten(input => raw_data:jobs)
 
    union all
    select 'workable', count(*)
    from {{ source('raw', 'raw_workable') }},
         lateral flatten(input => raw_data:jobs)
 
    union all
    select 'smartrecruiters', count(*)
    from {{ source('raw', 'raw_smartrecruiters') }},
         lateral flatten(input => raw_data)
 
    union all
    select 'jooble', count(*)
    from {{ source('raw', 'raw_jooble') }},
         lateral flatten(input => try_parse_json(raw_data:response_raw::string):jobs)
    where raw_data:http_status::number = 200
 
    union all
    select 'jsearch', count(*)
    from {{ source('raw', 'raw_jsearch') }},
         lateral flatten(input => try_parse_json(raw_data:response_raw::string):data)
    where raw_data:http_status::number = 200
),
 
staged_counts as (
    select 'ashby' as source_name, sum(copies_landed) as staged_copies from {{ ref('stg_ashby_jobs') }}
    union all
    select 'greenhouse',      sum(copies_landed) from {{ ref('stg_greenhouse_jobs') }}
    union all
    select 'workable',        sum(copies_landed) from {{ ref('stg_workable_jobs') }}
    union all
    select 'smartrecruiters', sum(copies_landed) from {{ ref('stg_smartrecruiters_jobs') }}
    union all
    select 'jooble',          sum(copies_landed) from {{ ref('stg_jooble_jobs') }}
    union all
    select 'jsearch',         sum(copies_landed) from {{ ref('stg_jsearch_jobs') }}
)
 
select
    r.source_name,
    r.raw_rows,
    coalesce(s.staged_copies, 0) as staged_copies
from raw_counts r
left join staged_counts s
    on r.source_name = s.source_name
where coalesce(s.staged_copies, 0) > r.raw_rows
   or (r.source_name not in ('ashby', 'greenhouse')
       and coalesce(s.staged_copies, 0) <> r.raw_rows)
