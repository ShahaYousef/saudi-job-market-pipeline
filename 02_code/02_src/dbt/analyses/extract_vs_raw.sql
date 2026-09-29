-- dbt/analyses/extract_vs_raw.sql
-- Job objects per source and collection date in RAW, to compare with SUM(jobs_kept) in <raw>/extract_log.csv
-- (latest row per source, board and ingest_date, outcome = 'saved'). Dates collected before extract_log.csv
-- existed have no log rows: compare only dates present in both.
--   py -m dbt.cli.main compile --select extract_vs_raw, then run target/compiled/.../extract_vs_raw.sql
{% for s in ['ashby', 'workable', 'greenhouse', 'smartrecruiters'] %}
select '{{ s }}'                                   as source_name,
       {{ ingest_date_from_path('file_name') }}    as ingest_date,
       count(*)                                    as files,
       sum(coalesce(array_size({{ 'raw_data' if s == 'smartrecruiters' else 'raw_data:jobs' }}), 0)) as jobs_in_raw
from {{ source('raw', 'raw_' ~ s) }}
group by 1, 2
{% if not loop.last %}union all{% endif %}
{% endfor %}
order by 1, 2
