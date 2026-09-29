-- dbt/macros/normalize_employment_type.sql
{#
    Maps each source's own spelling of employment type onto one team vocabulary.

    Measured values per source before this macro existed:
      ashby            FullTime, PartTime, Contract, Intern
      greenhouse       Full-time
      jsearch          Full-time, Part-time, Contract, Contractor, Internship, Temporary, Volunteer
      smartrecruiters  Full-time, Part-time, Contract, Intern
      workable         Full-time, Part-time, Contract, Other, plus 400 empty strings

    Added after the September 2026 JSearch collection: combined values. A posting open to
    both full-time and part-time ("Full-time and Part-time", "FULLTIME, PARTTIME") keeps that
    meaning as its own value, 'Full-time and Part-time'; any other combination maps to Other.
    No source sent a combined value before, so the earlier counts do not change.

    Comparison ignores case, hyphens and spaces, so "FullTime", "Full-time" and "full time"
    land on the same value.

    An unrecognised value is passed through unchanged rather than mapped to null. The
    accepted_values test on employment_type then fails, which is how a new spelling from a
    source gets noticed instead of silently disappearing.
#}

{% macro normalize_employment_type(column) %}
    case
        when lower({{ column }}) like '%full%time%' and lower({{ column }}) like '%part%time%'
            then 'Full-time and Part-time'
        when {{ column }} ilike '% and %' or {{ column }} like '%,%' then 'Other'
        else
            case lower(replace(replace(trim({{ column }}), '-', ''), ' ', ''))
                when 'fulltime'   then 'Full-time'
                when 'parttime'   then 'Part-time'
                when 'contract'   then 'Contract'
                when 'contractor' then 'Contract'
                when 'intern'     then 'Internship'
                when 'internship' then 'Internship'
                when 'temporary'  then 'Temporary'
                when 'volunteer'  then 'Volunteer'
                when 'other'      then 'Other'
                else nullif(trim({{ column }}), '')
            end
    end
{% endmacro %}