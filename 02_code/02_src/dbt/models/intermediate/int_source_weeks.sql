-- dbt/models/intermediate/int_source_weeks.sql
--
-- Grain: one row per source per week (Sunday to Saturday, Asia/Riyadh) with at least one
-- successful file.
--
-- is_full_pull says whether the source was collected completely in that week:
--   ATS          every board of the source was pulled successfully that week. Each board file is
--                the board's full list of open jobs, so a board pulled is a board complete. Only
--                boards that existed by the end of the week and ever held a posting are required:
--                a board with no posting in any pull (Ashby camunda, pulled once on 2026-09-24,
--                0 postings) cannot change a lifecycle, so missing it does not make a week partial.
--   Aggregators  the week repeated the source's baseline campaign: the share of the baseline
--                week's query labels that were run again successfully reaches
--                var('aggregator_campaign_coverage') (1.0 = every baseline query). A query
--                returns a ranked slice of the market, so a partial re-run (e.g. the general
--                query alone on 26 September) is not a pull of the whole source.
-- Evidence for the data quality report (sources collected per week): a count that changes between
-- two periods is read against it, because a source missing from a period looks like a change in
-- the market.

with files as (
    select * from {{ ref('int_landed_files') }}
    where is_successful_file
),

baseline_week as (
    select source_name, min(week_start_date) as baseline_week_start
    from files
    group by source_name
),

baseline_queries as (
    select distinct f.source_name, f.query_label
    from files f
    join baseline_week b
        on f.source_name = b.source_name
       and f.week_start_date = b.baseline_week_start
    where f.query_label is not null
),

repeated as (
    select f.source_name, f.week_start_date, count(distinct f.query_label) as baseline_queries_repeated
    from files f
    join baseline_queries q
        on f.source_name = q.source_name
       and f.query_label = q.query_label
    group by f.source_name, f.week_start_date
),

ats_boards as (
    -- boards that ever held a posting, with their first successful pull
    select source_name, board, min(pull_date) as first_pull
    from {{ ref('int_board_pulls') }}
    where source_type = 'ATS' and is_successful
    group by source_name, board
    having max(postings_landed) > 0
),

ats_expected as (
    -- per ATS source and week: the boards required by the end of the week, and how many were pulled
    select
        w.source_name,
        w.week_start_date,
        count(b.board)  as boards_expected,
        count(p.board)  as boards_expected_pulled
    from (select distinct source_name, week_start_date from files) w
    join ats_boards b
        on  b.source_name = w.source_name
        and b.first_pull <= dateadd('day', 6, w.week_start_date)
    left join (select distinct source_name, week_start_date, board from files) p
        on  p.source_name = b.source_name
        and p.week_start_date = w.week_start_date
        and p.board = b.board
    group by w.source_name, w.week_start_date
),

weeks as (
    select
        source_name,
        week_start_date,
        count(distinct pull_date)    as pull_days,
        count(distinct board)        as boards_pulled,
        count(distinct query_label)  as queries_run,
        count(*)                     as files_successful
    from files
    group by source_name, week_start_date
)

select
    {{ dbt_utils.generate_surrogate_key(['w.source_name', 'w.week_start_date']) }}          as source_week_sk,
    w.*,
    src.source_type,
    w.week_start_date = b.baseline_week_start                                               as is_baseline_week,
    bq.baseline_queries,
    coalesce(r.baseline_queries_repeated, 0)                                                as baseline_queries_repeated,
    e.boards_expected,
    e.boards_expected_pulled,
    case
        when src.source_type = 'ATS'
            then coalesce(e.boards_expected_pulled, 0) = coalesce(e.boards_expected, 0)
        else coalesce(r.baseline_queries_repeated, 0)
             >= ceil(bq.baseline_queries * {{ var('aggregator_campaign_coverage') }})
    end                                                                                     as is_full_pull
from weeks w
join baseline_week b
    on w.source_name = b.source_name
left join (
    select source_name, count(*) as baseline_queries from baseline_queries group by source_name
) bq
    on w.source_name = bq.source_name
left join repeated r
    on w.source_name = r.source_name
   and w.week_start_date = r.week_start_date
left join ats_expected e
    on  w.source_name = e.source_name
   and w.week_start_date = e.week_start_date
left join {{ ref('seed_sources') }} src
    on w.source_name = src.source_name
