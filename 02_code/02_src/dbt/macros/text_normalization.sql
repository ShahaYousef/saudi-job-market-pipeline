{#
    Text helpers for the intermediate layer.

    Snowflake regex has no \b word boundary, so whole-word removal pads the text with spaces
    and matches " word ". It runs twice so two noise words in a row are both removed.
#}

{# Lower-case, punctuation to spaces, whitespace collapsed. The base every *_norm column starts from. #}
{% macro normalize_text(column) %}
    nullif(trim(regexp_replace(regexp_replace(lower({{ column }}), '[[:punct:]]', ' '), '\\s+', ' ')), '')
{% endmacro %}


{% macro remove_words(expr, words) %}
    {%- set pattern = ' (' ~ (words | join('|')) ~ ') ' -%}
    nullif(trim(regexp_replace(regexp_replace(regexp_replace(
        ' ' || {{ expr }} || ' ', '{{ pattern }}', ' '), '{{ pattern }}', ' '), '\\s+', ' ')), '')
{% endmacro %}


{#
    Title key used ONLY for cross-source matching; the display title keeps its original form.
    Removes bracketed notes ("(Saudi National)"), hiring noise and location words that sources
    append to the same job differently, and expands common abbreviations. A title that is only a
    bracketed note ("(Accountant)") keeps the words inside the brackets, so it still has a key.

    Before that, two differences between sources that [[:punct:]] does not see are removed:
      - Unicode dashes, quotes and Arabic punctuation become spaces. [[:punct:]] covers ASCII
        only, so "Pricing Lead – Middle East" (JSearch) kept "–" as a word and did not meet
        "Pricing Lead - Middle East" (Jooble) in the exact tier.
      - "&" becomes "and": JSearch writes "IT Support and Network Administrator" where the
        employer board writes "IT Support & Network Administrator".
    Company keys are not changed here, because seed_company_aliases is stored in
    normalize_company() form.
#}
{% macro normalize_title(column) %}
    {%- set noise = ['urgent', 'urgently', 'hiring', 'required', 'needed', 'wanted', 'immediate',
                     'saudi national', 'saudi nationals', 'saudis only', 'saudi only',
                     'ksa', 'saudi arabia', 'saudi', 'riyadh', 'jeddah', 'dammam', 'khobar', 'al khobar'] -%}
    {%- set prepared = "regexp_replace(replace(lower(" ~ column ~ "), '&', ' and '), '[–—‐‑‒―’‘“”«»•·…،؛؟]', ' ')" -%}
    {%- set cleaned = "regexp_replace(" ~ prepared ~ ", '\\\\([^)]*\\\\)|\\\\[[^]]*\\\\]', ' ')" -%}
    {%- set base = "coalesce(" ~ normalize_text(cleaned) ~ ", " ~ normalize_text(prepared) ~ ")" -%}
    {%- set expanded = "regexp_replace(regexp_replace(regexp_replace(' ' || " ~ base ~ " || ' ', ' sr ', ' senior '), ' jr ', ' junior '), ' mgr ', ' manager ')" -%}
    {{ remove_words(expanded, noise) }}
{% endmacro %}


{# Company key used ONLY for matching: legal suffixes and page labels removed. #}
{% macro normalize_company(column) %}
    {%- set noise = ['company', 'co', 'ltd', 'limited', 'inc', 'llc', 'plc', 'corp', 'corporation',
                     'group', 'est', 'establishment', 'the', 'careers page', 'careers', 'jobs',
                     'ksa', 'saudi arabia', 'kingdom of saudi arabia', 'شركة', 'مؤسسة'] -%}
    {{ remove_words(normalize_text(column), noise) }}
{% endmacro %}


{#
    HTML to plain text. Greenhouse double-escapes its content (&lt;p&gt;, &amp;nbsp;), so entities
    are decoded first, then tags stripped, then the remaining entities decoded.
    Plain-text input (Ashby, JSearch, Jooble) passes through unchanged apart from whitespace.
#}
{% macro strip_html(column) %}
    nullif(trim(regexp_replace(
        replace(replace(replace(replace(
            regexp_replace(
                replace(replace(replace(replace(replace(
                    {{ column }}, '&lt;', '<'), '&gt;', '>'), '&quot;', '"'), '&#39;', ''''), '&amp;', '&'),
                '<[^>]*>', ' '),
            '&nbsp;', ' '), '&amp;', '&'), '&lt;', '<'), '&gt;', '>'),
        '\\s+', ' ')), '')
{% endmacro %}