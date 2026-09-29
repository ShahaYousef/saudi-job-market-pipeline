{#
    Sunday that starts the week of a date: the Saudi working week runs Sunday to Thursday, and the
    weekend is Friday and Saturday. dayofweekiso is 1 (Monday) to 7 (Sunday), so Sunday maps to
    itself and every other day goes back to the Sunday before it. Independent of the session's
    WEEK_START setting, and the same formula as dim_date.week_start_date.
#}
{% macro week_start(column) %}
    dateadd('day', -mod(dayofweekiso({{ column }}), 7), {{ column }})
{% endmacro %}
