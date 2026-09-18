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

    file_path = os.path.join(output_folder, f"{company}.json")

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(saudi_jobs, f, ensure_ascii=False, indent=2)

    print(f"Saved: {file_path}")
    print(f"Saudi jobs: {len(saudi_jobs)}")

print("Done!")
