
"""
Ashby Job Board API — raw data collection script (Saudi-filtered)
================================================
 
Ashby gives every company that uses it a PUBLIC job-board API, no API key
needed. You just need the company's "job board name" (a slug), which you
can find in their careers-page URL:
 
    https://jobs.ashbyhq.com/<job-board-name>
 
The API endpoint is:
    GET https://api.ashbyhq.com/posting-api/job-board/<job-board-name>
 
This script:
  1. Calls that endpoint for every board in JOB_BOARD_NAMES, retrying timeouts,
     HTTP 429 and 5xx (common/http_retry.py)
  2. Filters the "jobs" list down to Saudi-based postings only
     (via SAUDI_KEYWORDS matched against the "location" field)
  3. Saves that filtered result AS-IS: every job dict keeps every original key
  4. Writes ONE JSON file per company:
         <raw>/ashby/ingest_date=<YYYY-MM-DD>/<job_board_name>.json
  5. Logs one row per board to <raw>/extract_log.csv (common/extract_log.py)
 
A board that still fails after the retries is logged as 'failed' and gets no file, so dbt treats
it as "not pulled"; the other boards are still collected. The script exits with an error only
when every board failed.
"""
 
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
 
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
from common import config, extract_log, http_retry
 
SOURCE_ID = "ashby"
 
# ---------------------------------------------------------------------
# 1. CONFIG — add every Ashby company slug you want to pull from here
# ---------------------------------------------------------------------
JOB_BOARD_NAMES = [
    "sarjai",
    "alan",
    "immersivelabs",
    "elevenlabs",
    "lilt-production",
    "hopper",
    "checkout.com",
    "takein",
    "Nash",
    "lakeora",
    
]
 
BASE_DIR = config.raw_dir_for(SOURCE_ID)   # <raw>/ashby/, shared landing zone for every source
 
SAUDI_KEYWORDS = [
    "saudi", "saudi arabia", "ksa",
    "riyadh", "jeddah", "jiddah", "mecca", "makkah", "medina", "madinah",
    "dammam", "khobar", "al khobar", "dhahran", "jubail", "al jubail",
    "taif", "tabuk", "abha", "khamis mushait", "najran", "hail", "ha'il",
    "jazan", "jizan", "al kharj", "yanbu", "buraidah", "unaizah",
    "al ahsa", "al-ahsa", "hofuf", "qatif", "sakaka", "arar", "baha",
    "al baha",
]
 
 
def is_saudi_location(location: str) -> bool:
    # substring match: "hail" also matches "Thailand"; stg_ashby_jobs re-checks the country field
    location = (location or "").lower()
    return any(kw in location for kw in SAUDI_KEYWORDS)
 
 
# ---------------------------------------------------------------------
# 2. FETCH — one company's job board
# ---------------------------------------------------------------------
def fetch_job_board(job_board_name: str):
    """Raw JSON of one board, or None when the board does not exist (404).
    Raises http_retry.FetchError when the board still fails after the retries."""
    url = f"https://api.ashbyhq.com/posting-api/job-board/{job_board_name}"
    params = {"includeCompensation": "false"}  # set True if you also want salary bands
    status, data = http_retry.get_json(url, params=params, timeout=30)
    if status == 404:
        return None
    return data
 
 
# ---------------------------------------------------------------------
# 3. SAVE — write the Saudi-filtered response, untouched otherwise
# ---------------------------------------------------------------------
def save_filtered_snapshot(job_board_name: str, filtered_json: dict, ingest_date: str):
    out_dir = os.path.join(BASE_DIR, f"ingest_date={ingest_date}")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{job_board_name}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(filtered_json, f, ensure_ascii=False, indent=2)
    print(f"  [saved] {path}")
    return path
 
 
# ---------------------------------------------------------------------
# 4. MAIN — one board at a time; a failing board never stops the others
# ---------------------------------------------------------------------
def main():
    ingest_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    failed = 0
 
    for job_board_name in JOB_BOARD_NAMES:
        print(f"Fetching: {job_board_name}")
        try:
            raw = fetch_job_board(job_board_name)
            if raw is None:
                print(f"  [skip] '{job_board_name}' — no public job board found (404)")
                extract_log.log_board(SOURCE_ID, job_board_name, ingest_date, "not_found", http_status=404)
                continue
 
            jobs = raw.get("jobs", [])
            saudi_jobs = [j for j in jobs if is_saudi_location(j.get("location"))]
            print(f"  {len(jobs)} open jobs, {len(saudi_jobs)} Saudi-based")
 
            # saved even when empty: an empty file tells dbt this board WAS pulled and has
            # no open Saudi postings, so its old postings are marked closed
            filtered = dict(raw)
            filtered["jobs"] = saudi_jobs
            path = save_filtered_snapshot(job_board_name, filtered, ingest_date)
            extract_log.log_board(SOURCE_ID, job_board_name, ingest_date, "saved", http_status=200,
                                  jobs_returned=len(jobs), jobs_kept=len(saudi_jobs), file_path=path)
 
        except (http_retry.FetchError, OSError) as e:
            # OSError: the file could not be written (e.g. locked by OneDrive)
            failed += 1
            print(f"  [failed] '{job_board_name}' — {e}; no file written, board treated as not pulled")
            extract_log.log_board(SOURCE_ID, job_board_name, ingest_date, "failed",
                                  http_status=getattr(e, "status", None), error=str(e))
 
    print(f"\nDone. {len(JOB_BOARD_NAMES) - failed} of {len(JOB_BOARD_NAMES)} boards pulled.")
    if failed == len(JOB_BOARD_NAMES):
        sys.exit("Every board failed: check the network or the API before re-running.")
 
 
if __name__ == "__main__":
    main()
