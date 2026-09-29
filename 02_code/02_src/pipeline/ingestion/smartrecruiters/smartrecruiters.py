# pipeline/ingestion/smartrecruiters/smartrecruiters.py
"""
SmartRecruiters Posting API — raw data collection script
========================================================

SmartRecruiters gives every company that uses it a PUBLIC postings API, no API key needed:

    GET https://api.smartrecruiters.com/v1/companies/<company>/postings?country=sa
    GET https://api.smartrecruiters.com/v1/companies/<company>/postings/<id>   (detail)

This script:
  1. Pages through each company's Saudi postings (country=sa is filtered by the API),
     100 per page, retrying timeouts, HTTP 429 and 5xx (common/http_retry.py)
  2. Fetches each posting's detail and adds its "jobAd" (the description sections)
  3. Writes ONE JSON file per company into the shared raw landing zone:
         <raw>/smartrecruiters/ingest_date=<YYYY-MM-DD>/<company>_jobs.json
  4. Logs one row per company to <raw>/extract_log.csv (common/extract_log.py)

A file is written even when a company has no Saudi postings. A company whose listing still fails
after the retries is skipped and gets no file, so dbt treats it as "not pulled" rather than
"all postings closed". A failed detail request keeps the posting with jobAd = null.

Run from 02_code/02_src:  python pipeline/ingestion/smartrecruiters/smartrecruiters.py
"""

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
from common import config, extract_log, http_retry

SOURCE_ID = "smartrecruiters"

COMPANIES = (
    "JobsForHumanity",
    "QualityEducationCompany",
    "AccorHotel",
    "Workhint",
    "Boskalis",
    "FacilInternationalCompanyForHotelsFood",
    "ASSYSTEM",
    "EthosInteractive",
    "EICO",
    "SwissHospitality",
    "CREALOGIX",
    "RolandBerger",
    "BoschGroup",
    "bTRanz",
)

BASE_URL = "https://api.smartrecruiters.com/v1/companies"
BASE_DIR = config.raw_dir_for(SOURCE_ID)   # <raw>/smartrecruiters/
PAGE_SIZE = 100                            # API maximum; the default is 10


def fetch_job_detail(company: str, job_id: str):
    """Full posting detail (includes the description) for one job, or None on 404."""
    status, data = http_retry.get_json(f"{BASE_URL}/{company}/postings/{job_id}", timeout=60)
    return data if status == 200 else None


def fetch_company_postings(company: str) -> list:
    """All Saudi postings of one company, following offset pagination.
    Raises http_retry.FetchError when a page still fails after the retries."""
    offset = 0
    postings = []
    while True:
        status, data = http_retry.get_json(
            f"{BASE_URL}/{company}/postings",
            params={"offset": offset, "limit": PAGE_SIZE, "country": "sa"},
            timeout=60,
        )
        if status == 404:
            raise http_retry.FetchError(f"{BASE_URL}/{company}/postings", 404, "company not found (404)")
        jobs = data.get("content", [])
        print(f"  {len(jobs)} jobs | offset {offset}")
        if len(jobs) == 0:
            break
        postings.extend(jobs)
        offset += len(jobs)
        time.sleep(0.5)
    return postings


def main():
    ingest_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    out_dir = os.path.join(BASE_DIR, f"ingest_date={ingest_date}")
    os.makedirs(out_dir, exist_ok=True)
    total_saved = 0
    failed = 0

    for company in COMPANIES:
        print(f"Fetching {company}...")
        try:
            saudi_jobs = fetch_company_postings(company)

            print(f"  Fetching descriptions for {len(saudi_jobs)} jobs...")
            for job in saudi_jobs:
                try:
                    detail = fetch_job_detail(company, job["id"])
                    job["jobAd"] = detail.get("jobAd") if detail else None
                except http_retry.FetchError as e:
                    print(f"    [skip] job {job['id']} - {e}")
                    job["jobAd"] = None
                time.sleep(0.3)

            file_path = os.path.join(out_dir, f"{company}_jobs.json")
            with open(file_path, "w", encoding="utf-8") as f:
                json.dump(saudi_jobs, f, ensure_ascii=False, indent=2)
            print(f"  Saved: {file_path} ({len(saudi_jobs)} Saudi jobs)")
            extract_log.log_board(SOURCE_ID, company, ingest_date, "saved", http_status=200,
                                  jobs_returned=len(saudi_jobs), jobs_kept=len(saudi_jobs),
                                  file_path=file_path)
            total_saved += len(saudi_jobs)

        except (http_retry.FetchError, OSError) as e:
            failed += 1
            print(f"  [skip] {company}: listing failed ({e}), no file written")
            extract_log.log_board(SOURCE_ID, company, ingest_date, "failed",
                                  http_status=getattr(e, "status", None), error=str(e))

    print(f"\nDone. {total_saved} Saudi postings saved; {len(COMPANIES) - failed} of {len(COMPANIES)} "
          f"companies pulled ({datetime.now(timezone.utc).isoformat()}).")
    if failed == len(COMPANIES):
        sys.exit("Every company failed: check the network or the API before re-running.")


if __name__ == "__main__":
    main()