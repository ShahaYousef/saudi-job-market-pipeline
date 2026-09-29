-- dbt/models/intermediate/int_board_pulls.sql
--
-- Grain: one row per pull. For an ATS source a pull is one board on one ingest date; for an
-- aggregator it is the source on one collection date (Asia/Riyadh).
--
-- is_successful: at least one landed file of the pull holds a job list (int_landed_files). Only
-- successful pulls count as evidence for the lifecycle rules in int_job_listings and
-- int_job_openings, so a failed or throttled request cannot close every job on a board.
--
-- is_baseline_pull: the first successful pull of the board (ATS), or the first week of
-- collection of the source (aggregators, whose first campaign ran over several days). Everything
-- a baseline pull returned already existed before the pipeline looked, so none of it is new.

with pulls as (
    select
        source_name,
        board,
        pull_date,
        week_start_date,
        count(*)                                                    as files_landed,
        count_if(is_successful_file)                                as files_successful,
        sum(postings_in_file)                                       as postings_landed,
        count(distinct iff(is_successful_file, query_label, null))  as queries_successful,
        count_if(is_successful_file) > 0                            as is_successful
    from {{ ref('int_landed_files') }}
    group by source_name, board, pull_date, week_start_date
)

select
    {{ dbt_utils.generate_surrogate_key(['p.source_name', 'p.board', 'p.pull_date']) }}    as pull_sk,
    p.*,
    src.source_type,
    case
        when not p.is_successful then false
        when src.source_type = 'ATS'
            then p.pull_date = min(iff(p.is_successful, p.pull_date, null)) over (partition by p.source_name, p.board)
        else p.week_start_date = min(iff(p.is_successful, p.week_start_date, null)) over (partition by p.source_name)
    end                                                                                    as is_baseline_pull
from pulls p
left join {{ ref('seed_sources') }} src
    on p.source_name = src.source_name
