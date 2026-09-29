-- dbt/models/marts/dim_date.sql
--
-- One row per day, plus the Unknown member (-1) (data_model.md, section 6). Role-playing
-- dimension: fct_jobs joins it in six roles (posted, first seen, last seen, opening, open until,
-- disappeared). The range runs from the earliest date of any role (usually an old posting date)
-- to the latest of any role or the latest successful pull, so every role has a row.
-- Dates are Asia/Riyadh dates, taken in int_job_listings. week_start_date is the Sunday that
-- starts the week, matching the Saudi working week.

with bounds as (
    select
        least(coalesce(min(posting_date), min(first_seen_date)), min(first_seen_date))  as start_date,
        greatest(max(last_seen_date), max(open_until_date),
                 coalesce(max(disappeared_date), max(last_seen_date)), max(as_of_date))   as end_date
    from {{ ref('int_job_openings') }}
),

days as (
    select dateadd('day', row_number() over (order by seq4()) - 1, b.start_date) as full_date
    from table(generator(rowcount => 10000))
    cross join bounds b
    qualify full_date <= max(b.end_date) over ()
)

select
    to_number(to_char(full_date, 'YYYYMMDD'))                   as date_sk,
    full_date,
    dayname(full_date)                                          as day_of_week,
    {{ week_start('full_date') }}                               as week_start_date,
    month(full_date)                                            as month,
    quarter(full_date)                                          as quarter,
    year(full_date)                                             as year,
    dayofweekiso(full_date) in (5, 6)                           as is_weekend   -- Friday and Saturday
from days

union all

select -1, null, 'Unknown', null, null, null, null, null
