{#
    Helpers shared by the four ATS staging models (Ashby, Workable, Greenhouse, SmartRecruiters).

    ATS files carry no collection timestamp of their own (unlike the Jooble/JSearch envelopes),
    so the collection date is read from the landing path:
        ashby/ingest_date=2026-09-16/alan.json  ->  2026-09-16
#}

{% macro ingest_date_from_path(column) %}
    to_date(regexp_substr({{ column }}, 'ingest_date=([0-9]{4}-[0-9]{2}-[0-9]{2})', 1, 1, 'e', 1))
{% endmacro %}


{#
    Turns a DATE into midnight UTC as TIMESTAMP_TZ.
    Used for ingest_date and for date-only source fields (Workable published_on),
    so they never pick up the Snowflake session time zone by accident.
#}
{% macro date_to_utc_timestamp(column) %}
    timestamp_tz_from_parts(year({{ column }}), month({{ column }}), day({{ column }}), 0, 0, 0, 0, 'UTC')
{% endmacro %}


{#
    The board a landed file belongs to, taken from the file name:
        workable/ingest_date=2026-09-16/salla.json               ->  salla
        greenhouse/ingest_date=2026-09-16/cssmerge_jobs.json     ->  cssmerge
        smartrecruiters/ingest_date=2026-09-25/AccorHotel_jobs.json  ->  accorhotel
    A board is the unit that gets pulled, so "was this board pulled again?" is answered by
    the file, not by any field inside the payload. Lower-cased, and a trailing "_jobs" removed,
    so the same board groups together across snapshots even though some sources' file names
    changed (SmartRecruiters: <company>.json -> <company>_jobs.json; Greenhouse has both forms).
#}
{% macro board_from_path(column) %}
    regexp_replace(lower(split_part(split_part({{ column }}, '/', -1), '.json', 1)), '_jobs$', '')
{% endmacro %}