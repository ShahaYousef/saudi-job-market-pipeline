{# dbt/macros/export_marts.sql #}
{#
    Unloads the ten MARTS tables to ADLS, into the "curated" container, as Parquet:

        curated/<table>/export_date=YYYY-MM-DD/<table>_<run_id>.parquet

    - curated is a separate container from raw: raw holds only what the sources returned and is
      never modified; curated holds the modelled result.
    - Every export gets its own file name (run_id), so an earlier export is never overwritten,
      the same rule as raw.
    - Parquet keeps column names and types (dates, numbers, booleans). final_datasets/ in the
      repo holds the same tables as CSV for people.

        py -m dbt.cli.main run-operation export_marts
        py -m dbt.cli.main run-operation export_marts --args "{run_id: 20260926T090000Z}"

    Needs the stage in snowflake/curated_stage.sql. A failed unload raises an error, so the
    pipeline runner stops and records the failed step.
#}

{% macro export_marts(run_id=none) %}
    {% set tables = ['fct_jobs', 'bridge_job_skill', 'dim_job_posting', 'dim_company', 'dim_location',
                     'dim_role', 'dim_job_attributes', 'dim_skill', 'dim_date', 'dim_source'] %}
    {% set stage = var('curated_stage', 'job_pipeline_db.marts.curated_stage') %}
    {% set export_date = run_started_at.strftime('%Y-%m-%d') %}
    {% set tag = run_id if run_id else run_started_at.strftime('%Y%m%dT%H%M%SZ') %}

    {% for t in tables %}
        {% set path = t ~ '/export_date=' ~ export_date ~ '/' ~ t ~ '_' ~ tag ~ '.parquet' %}
        {% set sql %}
            copy into @{{ stage }}/{{ path }}
            from {{ ref(t) }}
            file_format = (type = parquet)
            header = true
            single = true
            max_file_size = 1000000000
        {% endset %}
        {% set result = run_query(sql) %}

        {# COPY INTO <location> returns rows_unloaded, input_bytes, output_bytes #}
        {% set ns = namespace(idx=none, rows=0) %}
        {% for name in result.column_names %}
            {% if name | lower == 'rows_unloaded' %}{% set ns.idx = loop.index0 %}{% endif %}
        {% endfor %}
        {% if ns.idx is not none %}
            {% for row in result.rows %}{% set ns.rows = ns.rows + (row[ns.idx] or 0) %}{% endfor %}
        {% endif %}
        {{ log('export_marts  ' ~ t ~ ': ' ~ ns.rows ~ ' rows -> curated/' ~ path, info=True) }}
    {% endfor %}
{% endmacro %}