-- dbt/macros/matching.sql
{#
    Helpers for cross-source matching (data_model.md, section 8.4).

    level_signature(title): the level words a normalized title contains, in a fixed order, as one
    string. A fuzzy pair is accepted only when both titles have the same signature, because the
    word that separates two roles usually comes last and a similarity score barely sees it:
    Jaro-Winkler scores "data analyst" against "data analyst intern" at 92.
    demi, ii, iii and iv are ranks and grades found in the labelled pairs and the audit of the fuzzy
    merges (data_model.md, section 8.7): "Chef de Partie" and "Demi Chef de Partie",
    "Technician I" and "Technician II", "Project Manager" and "Project Manager III" are two jobs.
    2, 3 and 4 are the same grades written as numbers and count as ii, iii and iv: the second
    audit found "Commissioning Specialist-2" merged with "Commissioning Specialist".
#}
{% macro level_words() %}
    {{ return(['intern', 'internship', 'trainee', 'apprentice', 'assistant', 'associate', 'junior',
               'senior', 'lead', 'head', 'principal', 'manager', 'director', 'chief', 'deputy', 'vice',
               'demi', 'ii', 'iii', 'iv', '2', '3', '4']) }}
{% endmacro %}

{% macro level_signature(column) %}
    (
    {%- for w in level_words() %}
        {%- set label = {'internship': 'intern', '2': 'ii', '3': 'iii', '4': 'iv'}.get(w, w) %}
        iff(' ' || {{ column }} || ' ' like '% {{ w }} %', '{{ label }} ', '')
        {%- if not loop.last %} ||{% endif %}
    {%- endfor %}
    )
{% endmacro %}
