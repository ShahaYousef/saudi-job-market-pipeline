{# dbt/macros/load_raw.sql #}
{#
    Loads new landed files from the ADLS external stage into the RAW tables: the same COPY INTO as
    snowflake/job_pipeline_snowflake.sql, run through the dbt connection, so the pipeline runner
    needs no second set of Snowflake credentials.

        py -m dbt.cli.main run-operation load_raw
        py -m dbt.cli.main run-operation load_raw --args "{sources: [ashby, workable]}"

    COPY INTO remembers the files it has loaded and skips them, so re-running is safe.
    A file that cannot be parsed aborts that COPY (ON_ERROR = ABORT_STATEMENT, the default),
    and run-operation then exits with an error, which stops the runner before dbt build.
#}

{% macro load_raw_sql(source_name) %}
copy into {{ source('raw', 'raw_' ~ source_name) }} (raw_data, file_name)
from (
    select $1, metadata$filename
    from @{{ var('raw_stage', 'job_pipeline_db.raw.raw_stage') }}/{{ source_name }}/
)
file_format = (type = json)
pattern = '.*[.]json'
{% endmacro %}


{% macro load_raw(sources=none) %}
    {% set all_sources = ['ashby', 'workable', 'greenhouse', 'smartrecruiters', 'jooble', 'jsearch'] %}
    {% set selected = sources if sources else all_sources %}

    {% for s in selected %}
        {% if s not in all_sources %}
            {{ exceptions.raise_compiler_error("load_raw: unknown source '" ~ s ~ "'") }}
        {% endif %}

        {% set result = run_query(load_raw_sql(s)) %}

        {# COPY returns one row per loaded file, or a single status row when nothing was new #}
        {% set ns = namespace(rows_idx=none, rows=0) %}
        {% for name in result.column_names %}
            {% if name | lower == 'rows_loaded' %}{% set ns.rows_idx = loop.index0 %}{% endif %}
        {% endfor %}

        {% if ns.rows_idx is none %}
            {{ log('load_raw  ' ~ s ~ ': no new files', info=True) }}
        {% else %}
            {% for row in result.rows %}
                {% set ns.rows = ns.rows + (row[ns.rows_idx] or 0) %}
            {% endfor %}
            {{ log('load_raw  ' ~ s ~ ': ' ~ (result.rows | length) ~ ' new file(s), '
                   ~ ns.rows ~ ' row(s) loaded', info=True) }}
        {% endif %}
    {% endfor %}
{% endmacro %}
