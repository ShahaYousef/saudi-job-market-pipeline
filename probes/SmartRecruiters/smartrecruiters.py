import requests
import json
import os
import time

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

script_folder = os.path.dirname(os.path.abspath(__file__))
output_folder = os.path.join(script_folder, "Data Sample")

os.makedirs(output_folder, exist_ok=True)


def fetch_job_detail(company: str, job_id: str) -> dict:
    """Fetches full posting detail (includes the description) for one job."""
    response = requests.get(
        f"{BASE_URL}/{company}/postings/{job_id}",
        timeout=60
    )
    response.raise_for_status()
    return response.json()


for company in COMPANIES:
    print(f"Fetching {company}...")

    offset = 0
    saudi_jobs = []

    while True:
        response = requests.get(
            f"{BASE_URL}/{company}/postings",
            params={
                "offset": offset,
                "country": "sa"
            },
            timeout=60
        )

        response.raise_for_status()

        data = response.json()
        jobs = data.get("content", [])

        print(f"  {len(jobs)} jobs | offset {offset}")

        saudi_jobs.extend(jobs)

        if len(jobs) == 0:
            break

        offset += len(jobs)
        time.sleep(0.5)

    
    print(f"  Fetching descriptions for {len(saudi_jobs)} jobs...")
    for job in saudi_jobs:
        try:
            detail = fetch_job_detail(company, job["id"])
            job["jobAd"] = detail.get("jobAd")  
        except requests.exceptions.RequestException as e:
            print(f"    [skip] job {job['id']} â {type(e).__name__}")
            job["jobAd"] = None
        time.sleep(0.3)  

    file_path = os.path.join(output_folder, f"{company}.json")

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(saudi_jobs, f, ensure_ascii=False, indent=2)

    print(f"Saved: {file_path}")
    print(f"Saudi jobs: {len(saudi_jobs)}")

print("Done!")
