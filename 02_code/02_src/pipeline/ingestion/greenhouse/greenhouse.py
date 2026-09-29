# pipeline/ingestion/greenhouse/greenhouse.py
"""
Greenhouse Job Board API — raw data collection script (Saudi-filtered)
======================================================================

Greenhouse gives every company that uses it a PUBLIC job-board API, no API key needed:

    GET https://boards-api.greenhouse.io/v1/boards/<board_token>/jobs?content=true

This script:
  1. Calls that endpoint for every board in BOARDS, retrying timeouts, HTTP 429 and 5xx
     (common/http_retry.py). A 404 is no longer retried: the board does not exist.
  2. Keeps only postings whose location matches SAUDI_KEYWORDS
  3. Saves the response otherwise untouched (same top-level shape, every job key kept)
  4. Writes ONE JSON file per board into the shared raw landing zone:
         <raw>/greenhouse/ingest_date=<YYYY-MM-DD>/<board_token>_jobs.json
  5. Logs one row per board to <raw>/extract_log.csv (common/extract_log.py)

A file is written even when a board has no Saudi postings, so dbt can tell
"this board was pulled and has nothing open" from "this board was not pulled".

Run from 02_code/02_src:  python pipeline/ingestion/greenhouse/greenhouse.py
"""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
from common import config, extract_log, http_retry

SOURCE_ID = "greenhouse"

# ---------------------------------------------------------------------
# 1. CONFIG — every Greenhouse board token to pull. Adding a board here is
#    the only change needed; no other edit between runs.
# ---------------------------------------------------------------------
BOARDS = [
    "artefact",
    "brkz",
    "careem",
    "cssmerge",
    "decimainternational",
    "dmgevents",
    "hala",
    "jensenhughes",
    "kitchenpark",
    "lucidmotors",
    "menaconsultant",
    "minio",
    "namaa",
    "ogilvymena",
    "pronto",
    "recruitis",
    "tamara",
]

BASE_DIR = config.raw_dir_for(SOURCE_ID)   # <raw>/greenhouse/

SAUDI_KEYWORDS = [
    "saudi arabia", "saudi", "ksa", "riyadh", "jeddah", "dammam", "khobar", "al khobar",
    "dhahran", "jubail", "mecca", "makkah", "medina", "madinah", "jazan", "jizan", "tabuk",
    "abha", "taif", "yanbu", "al ahsa", "hofuf", "neom", "king abdullah economic city",
    "eastern province", "western province",
]

SLEEP_BETWEEN_BOARDS = 1


# ---------------------------------------------------------------------
# 2. FETCH — one board
# ---------------------------------------------------------------------
def fetch_board(board_token: str):
    """Raw JSON of one board, or None when the board does not exist (404).
    Raises http_retry.FetchError when the board still fails after the retries."""
    url = f"https://boards-api.greenhouse.io/v1/boards/{board_token}/jobs"
    status, data = http_retry.get_json(url, params={"content": "true"}, timeout=60)
    if status == 404:
        return None
    return data


def is_saudi_location(job: dict) -> bool:
    # "or ''" also covers a location whose name is null (the old .get("name", "") did not)
    location = ((job.get("location") or {}).get("name") or "").lower()
    return any(keyword in location for keyword in SAUDI_KEYWORDS)


# ---------------------------------------------------------------------
# 3. SAVE — Saudi-filtered response, otherwise untouched
# ---------------------------------------------------------------------
def save_snapshot(board_token: str, data: dict, ingest_date: str):
    out_dir = os.path.join(BASE_DIR, f"ingest_date={ingest_date}")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{board_token}_jobs.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=4)
    print(f"  [saved] {path}")
    return path


# ---------------------------------------------------------------------
# 4. MAIN — one board at a time; a failing board never stops the others
# ---------------------------------------------------------------------
def main():
    ingest_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    total_saved = 0
    failed = 0

    for board_token in BOARDS:
        print(f"Fetching: {board_token}")
        try:
            data = fetch_board(board_token)
            if data is None:
                print(f"  [skip] {board_token}: no public board found (404)")
                extract_log.log_board(SOURCE_ID, board_token, ingest_date, "not_found", http_status=404)
                continue

            jobs = data.get("jobs", [])
            saudi_jobs = [j for j in jobs if is_saudi_location(j)]
            print(f"  {len(jobs)} open jobs, {len(saudi_jobs)} Saudi-based")

            data["jobs"] = saudi_jobs
            path = save_snapshot(board_token, data, ingest_date)
            extract_log.log_board(SOURCE_ID, board_token, ingest_date, "saved", http_status=200,
                                  jobs_returned=len(jobs), jobs_kept=len(saudi_jobs), file_path=path)
            total_saved += len(saudi_jobs)

        except (http_retry.FetchError, OSError) as e:
            failed += 1
            print(f"  [failed] {board_token}: {e}; no file written, board treated as not pulled")
            extract_log.log_board(SOURCE_ID, board_token, ingest_date, "failed",
                                  http_status=getattr(e, "status", None), error=str(e))
        time.sleep(SLEEP_BETWEEN_BOARDS)

    print(f"\nDone. {total_saved} Saudi postings saved; {len(BOARDS) - failed} of {len(BOARDS)} boards "
          f"pulled ({datetime.now(timezone.utc).isoformat()}).")
    if failed == len(BOARDS):
        sys.exit("Every board failed: check the network or the API before re-running.")


if __name__ == "__main__":
    main()