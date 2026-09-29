-- dbt/tests/assert_ats_latest_pull_not_collapsed.sql
-- Guard for the lifecycle on the employer boards (data_model.md, section 7.1; dbt/DATA_QUALITY.md).
--
-- An ATS file is read as a full snapshot, and an empty file means "pulled, nothing open". So a board
-- whose pull comes back empty or cut short (API change, a renamed field, a broken filter) would mark
-- every posting of that board as disappeared at once (K = 1), and every other test would still pass.
--
-- Checked per board, not per source: one large board losing its list (AccorHotel holds about a third
-- of the SmartRecruiters postings) would not move a source total below half. For each ATS board,
-- compares its latest successful pull with its successful pull before, and fails when the latest
-- holds less than var('ats_collapse_ratio') of the postings of the one before. Boards whose pull
-- before held fewer than var('ats_collapse_min_postings') postings are skipped. Every returned row
-- is a failure: `dbt build` fails, no export.

with board_pulls as (
    select
        source_name,
        board,
        pull_date,
        postings_landed,
        lag(pull_date)       over (partition by source_name, board order by pull_date) as previous_pull_date,
        lag(postings_landed) over (partition by source_name, board order by pull_date) as previous_postings
    from {{ ref('int_board_pulls') }}
    where source_type = 'ATS'
      and is_successful
    qualify row_number() over (partition by source_name, board order by pull_date desc) = 1
)

select
    source_name,
    board,
    previous_pull_date,
    previous_postings,
    pull_date       as latest_pull_date,
    postings_landed as latest_postings
from board_pulls
where previous_postings >= {{ var('ats_collapse_min_postings') }}
  and postings_landed < {{ var('ats_collapse_ratio') }} * previous_postings
