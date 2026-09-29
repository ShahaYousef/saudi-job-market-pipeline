{#
    Overrides dbt's default schema naming.

    By default dbt builds a model with +schema: marts into "<target schema>_marts"
    (e.g. STAGING_MARTS). This project wants one schema per layer with a plain name:
    STAGING, INTERMEDIATE, MARTS and SEEDS, so the layers are visible in Snowflake and
    Power BI can be pointed at MARTS only. A node without +schema falls back to the
    target schema from profiles.yml.
#}

{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}