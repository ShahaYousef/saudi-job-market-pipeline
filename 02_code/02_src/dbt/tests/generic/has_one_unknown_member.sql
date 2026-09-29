{# dbt/tests/generic/has_one_unknown_member.sql #}
{#
    Every dimension holds exactly one Unknown member, so a fact row with a missing value points
    to it instead of carrying a null foreign key. Fails when the count of Unknown rows is not 1.
    dim_date passes unknown_value=-1; the other dimensions use the default '-1'.
#}
{% test has_one_unknown_member(model, column_name, unknown_value="'-1'") %}
select count(*) as unknown_rows
from {{ model }}
where {{ column_name }} = {{ unknown_value }}
having count(*) <> 1
{% endtest %}