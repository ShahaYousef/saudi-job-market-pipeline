"""
Workable public Job Board API — raw data collection script (Saudi-filtered)
=========================================================

Like Ashby, Workable gives every company that uses it a PUBLIC job-board
endpoint, no API key needed. You just need the company's "account slug",
which you can find in their careers-page URL:

    https://apply.workable.com/<account_slug>/
                                 ^^^^^^^^^^^^^
                                 this part

Example: https://apply.workable.com/foodics/  ->  account_slug = "foodics"
(legacy URLs look like https://foodics.workable.com/ — same slug either way)

The endpoint is:
    GET https://apply.workable.com/api/v1/widget/accounts/<account_slug>?details=true

`details=true` is important — without it you only get summary fields, no
full job description.

This script mirrors Ashby.py:
  1. Calls that endpoint for one or more companies, with retries on
     timeout/connection errors so one slow company doesn't kill the run
  2. Filters the "jobs" list down to Saudi-based postings only, using
     the real structured country fields (is_saudi_job below), falling
     back to keyword matching only when no structured location data
     exists at all
  3. Saves that filtered result AS-IS — no field extraction, no
     renaming, no reshaping. Every job dict keeps every original key
     exactly as Workable returned it; only the list of jobs is filtered.
  4. Writes ONE JSON file per company, landed in the same raw-layer
     folder structure used elsewhere in the pipeline:

         adls_upload/workable/ingest_date=<YYYY-MM-DD>/<account_slug>.json

     Each file's top-level shape is unchanged from the API response
     (e.g. {"jobs": [...]}), just with "jobs" filtered to Saudi only.
"""

import requests
import json
import os
import time
from datetime import datetime, timezone

# ---------------------------------------------------------------------
# 1. CONFIG — add every Workable account slug you want to pull from here
# ---------------------------------------------------------------------
WORKABLE_ACCOUNTS = [

     'eramtalent-1',
    'jasarapmc',

    "foodics",
    "salla",
    "qiddiya-investment-company-1",
     'ananinja',
      'fuku',
        'lamdax',
          'nowlun',
            'foodics',
             'beond',
               'tawantech',




    # add more confirmed Saudi/regional Workable accounts here
]

BASE_DIR = "adls_upload/workable"   # raw landing layer, same layout as the pipeline's ADLS drop

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
# 2. FETCH — one company's job board (with retries, like the Ashby script)
# ---------------------------------------------------------------------
def fetch_job_board(account_slug: str, max_retries: int = 3) -> dict:
    """Calls the Workable public widget API for one company.

    Retries on timeout/connection errors instead of crashing the whole
    run. Returns None if the account doesn't exist (404) or every retry
    attempt fails.
    """
    url = f"https://apply.workable.com/api/v1/widget/accounts/{account_slug}"
    params = {"details": "true"}  # include full job descriptions

    for attempt in range(1, max_retries + 1):
        try:
            response = requests.get(url, params=params, timeout=30)
        except (requests.exceptions.Timeout, requests.exceptions.ConnectionError) as e:
            print(f"  [retry {attempt}/{max_retries}] '{account_slug}' — {type(e).__name__}, retrying...")
            time.sleep(2 * attempt)
            continue

        if response.status_code == 404:
            print(f"  [skip] '{account_slug}' — no public job board found (404)")
            return None

        response.raise_for_status()
        return response.json()

    print(f"  [failed] '{account_slug}' — gave up after {max_retries} attempts, skipping")
    return None


# ---------------------------------------------------------------------
# 3. SAVE — write the Saudi-filtered response, untouched otherwise,
#    into the same ingest_date= folder layout as the rest of the raw layer
# ---------------------------------------------------------------------
def save_filtered_snapshot(account_slug: str, filtered_json: dict, ingest_date: str) -> None:
    out_dir = os.path.join(BASE_DIR, f"ingest_date={ingest_date}")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{account_slug}.json")

    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(filtered_json, f, ensure_ascii=False, indent=2)
        print(f"  [saved] {path}")
    except PermissionError:
        print(
            f"  Could not write '{path}' — it's likely open in another "
            "program or locked by OneDrive syncing. Close it and rerun."
        )


# ---------------------------------------------------------------------
# 4. LOCATION HELPER — verified against a real Workable response.
#    Each job carries its OWN single location at the top level
#    (job["city"], job["state"], job["country"]) — confirmed real
#    fields, NOT "location_str" / "country_name" (that earlier version
#    was based on a blog post with outdated/wrong field names).
#
#    Important: when the same role is open in several cities, Workable
#    does NOT put multiple entries in one job's locations[] — it
#    returns a SEPARATE job object per location, all sharing the same
#    title but a different shortcode/url. So each job here really only
#    has one location, and job["locations"] is just that one location
#    wrapped in a list.
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
    """Checks the real 'country' field directly — far more reliable than
    keyword-matching a flattened location string. Falls back to keyword
    matching only if country/countryCode are both missing."""
    if (job.get("country") or "").strip().lower() == "saudi arabia":
        return True
    for entry in job.get("locations") or []:
        country = (entry.get("country") or "").strip().lower()
        code = (entry.get("countryCode") or "").strip().upper()
        if country == "saudi arabia" or code == "sa":
            return True

    # fallback: no structured country data at all — try keyword matching
    # on whatever location text is available
    if not (job.get("country") or job.get("locations")):
        return is_saudi_location(resolve_location(job))

    return False


# ---------------------------------------------------------------------
# 5. MAIN — loop over all companies, filter by location only, save raw JSON
# ---------------------------------------------------------------------
def main():
    ingest_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")

    for account_slug in WORKABLE_ACCOUNTS:
        print(f"Fetching: {account_slug}")
        raw = fetch_job_board(account_slug)

        if raw is None:
            continue

        jobs = raw.get("jobs", [])
        print(f"  found {len(jobs)} open jobs")

        # keep only jobs with a real title and a real apply link
        # (NOTE: earlier version of this filter also checked
        # job["state"] == "published" — that was wrong. "state" in the
        # real API response is a region name like "Makkah Province",
        # not a publish-status flag, so that check was silently
        # dropping almost every job. Removed.)
        valid_jobs = [
            j for j in jobs
            if j.get("title") and (j.get("url") or j.get("shortlink"))
        ]

        saudi_jobs = [j for j in valid_jobs if is_saudi_job(j)]
        print(f"  {len(saudi_jobs)} of them are Saudi-based")

        if not saudi_jobs:
            continue

        # keep the original top-level response shape, no transformation,
        # just the "jobs" list filtered down to Saudi postings
        filtered = dict(raw)
        filtered["jobs"] = saudi_jobs

        save_filtered_snapshot(account_slug, filtered, ingest_date)

    print("\nDone.")


if __name__ == "__main__":
    main()
