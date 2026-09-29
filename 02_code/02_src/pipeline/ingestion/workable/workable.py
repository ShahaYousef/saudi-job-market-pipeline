# pipeline/ingestion/workable/workable.py
"""
Workable public Job Board API — raw data collection script (Saudi-filtered)
=========================================================

Like Ashby, Workable gives every company that uses it a PUBLIC job-board
endpoint, no API key needed. The account slug is in the careers-page URL:

    https://apply.workable.com/<account_slug>/

The endpoint is:
    GET https://apply.workable.com/api/v1/widget/accounts/<account_slug>?details=true

`details=true` is important — without it you only get summary fields, no
full job description.

This script:
  1. Calls that endpoint for every account in WORKABLE_ACCOUNTS, retrying timeouts,
     HTTP 429 and 5xx (common/http_retry.py). Before this change a single 429 or 5xx raised
     an uncaught HTTPError and stopped the run, so the remaining accounts were not pulled.
  2. Filters the "jobs" list down to Saudi-based postings, using the structured country
     fields (is_saudi_job below), falling back to keyword matching only when no structured
     location data exists at all
  3. Saves that filtered result AS-IS: every job dict keeps every original key
  4. Writes ONE JSON file per company:
         <raw>/workable/ingest_date=<YYYY-MM-DD>/<account_slug>.json
  5. Logs one row per account to <raw>/extract_log.csv (common/extract_log.py)
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
from common import config, extract_log, http_retry

SOURCE_ID = "workable"

# ---------------------------------------------------------------------
# 1. CONFIG — add every Workable account slug you want to pull from here
#    (the previous list had "foodics" twice; each account is listed once)
# ---------------------------------------------------------------------
WORKABLE_ACCOUNTS = [
    "eramtalent-1",
    "jasarapmc",
    "foodics",
    "salla",
    "qiddiya-investment-company-1",
    "ananinja",
    "fuku",
    "lamdax",
    "nowlun",
    "beond",
    "tawantech",
    # add more confirmed Saudi/regional Workable accounts here
]

BASE_DIR = config.raw_dir_for(SOURCE_ID)   # <raw>/workable/, shared landing zone for every source

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
    location = (location or "").lower()
    return any(kw in location for kw in SAUDI_KEYWORDS)


# ---------------------------------------------------------------------
# 2. FETCH — one company's job board
# ---------------------------------------------------------------------
def fetch_job_board(account_slug: str):
    """Raw JSON of one account, or None when the account does not exist (404).
    Raises http_retry.FetchError when the account still fails after the retries."""
    url = f"https://apply.workable.com/api/v1/widget/accounts/{account_slug}"
    status, data = http_retry.get_json(url, params={"details": "true"}, timeout=30)
    if status == 404:
        return None
    return data


# ---------------------------------------------------------------------
# 3. SAVE — write the Saudi-filtered response, untouched otherwise
# ---------------------------------------------------------------------
def save_filtered_snapshot(account_slug: str, filtered_json: dict, ingest_date: str):
    out_dir = os.path.join(BASE_DIR, f"ingest_date={ingest_date}")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{account_slug}.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(filtered_json, f, ensure_ascii=False, indent=2)
    print(f"  [saved] {path}")
    return path


# ---------------------------------------------------------------------
# 4. LOCATION HELPER — verified against a real Workable response.
#    Each job carries its OWN single location at the top level
#    (job["city"], job["state"], job["country"]). When the same role is open in
#    several cities, Workable returns a SEPARATE job object per location, all sharing
#    the same shortcode.
# ---------------------------------------------------------------------
def resolve_location(job: dict) -> str:
    city = (job.get("city") or "").strip()
    state = (job.get("state") or "").strip()
    country = (job.get("country") or "").strip()
    parts = [p for p in [city, state, country] if p]
    if parts:
        return ", ".join(parts)

    # fallback to locations[] in the rare case the top-level fields are empty
    for entry in job.get("locations") or []:
        c = (entry.get("city") or "").strip()
        r = (entry.get("region") or "").strip()
        co = (entry.get("country") or "").strip()
        bits = [p for p in [c, r, co] if p]
        if bits:
            return ", ".join(bits)

    return "Unknown"


def is_saudi_job(job: dict) -> bool:
    """Checks the real 'country' field directly; keyword matching only when
    country/countryCode are both missing."""
    if (job.get("country") or "").strip().lower() == "saudi arabia":
        return True
    for entry in job.get("locations") or []:
        country = (entry.get("country") or "").strip().lower()
        code = (entry.get("countryCode") or "").strip().upper()
        if country == "saudi arabia" or code == "SA":
            return True

    # fallback: no structured country data at all — try keyword matching
    if not (job.get("country") or job.get("locations")):
        return is_saudi_location(resolve_location(job))

    return False


# ---------------------------------------------------------------------
# 5. MAIN — one account at a time; a failing account never stops the others
# ---------------------------------------------------------------------
def main():
    ingest_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    failed = 0

    for account_slug in WORKABLE_ACCOUNTS:
        print(f"Fetching: {account_slug}")
        try:
            raw = fetch_job_board(account_slug)
            if raw is None:
                print(f"  [skip] '{account_slug}' — no public job board found (404)")
                extract_log.log_board(SOURCE_ID, account_slug, ingest_date, "not_found", http_status=404)
                continue

            jobs = raw.get("jobs", [])
            # keep only jobs with a real title and a real apply link
            valid_jobs = [j for j in jobs if j.get("title") and (j.get("url") or j.get("shortlink"))]
            saudi_jobs = [j for j in valid_jobs if is_saudi_job(j)]
            print(f"  {len(jobs)} open jobs, {len(saudi_jobs)} Saudi-based")

            # saved even when empty: an empty file tells dbt this board WAS pulled and has
            # no open Saudi postings, so its old postings are marked closed
            filtered = dict(raw)
            filtered["jobs"] = saudi_jobs
            path = save_filtered_snapshot(account_slug, filtered, ingest_date)
            extract_log.log_board(SOURCE_ID, account_slug, ingest_date, "saved", http_status=200,
                                  jobs_returned=len(jobs), jobs_kept=len(saudi_jobs), file_path=path)

        except (http_retry.FetchError, OSError) as e:
            failed += 1
            print(f"  [failed] '{account_slug}' — {e}; no file written, account treated as not pulled")
            extract_log.log_board(SOURCE_ID, account_slug, ingest_date, "failed",
                                  http_status=getattr(e, "status", None), error=str(e))

    print(f"\nDone. {len(WORKABLE_ACCOUNTS) - failed} of {len(WORKABLE_ACCOUNTS)} accounts pulled.")
    if failed == len(WORKABLE_ACCOUNTS):
        sys.exit("Every account failed: check the network or the API before re-running.")


if __name__ == "__main__":
    main()