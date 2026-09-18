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
    "IKEA",
    "ALHLEI",
    "ASSYSTEM",
    "Tahaluf",
    "KMCC",
    "Egis",
    "EthosInteractive",
    "EICO",
    "ITSecurityCT",
    "SwissHospitality",
    "SellAnyCar",
    "CREALOGIX",
    "DeltaElectronics",
    "RolandBerger",
    "InformaGroup",
    "BoschGroup",
    "bTRanz",
    "SmithsGroup",
    "AvtechSolution",
    "SyntessLanguageGroup",
)

BASE_URL = "https://api.smartrecruiters.com/v1/companies"

output_folder = os.path.join("SmartRecruiters", "Data sample")
os.makedirs(output_folder, exist_ok=True)

for company in COMPANIES:
    print(f"Fetching {company}...")

    offset = 0
    saudi_jobs = []

    while True:
        response = requests.get(
            f"{BASE_URL}/{company}/postings",
            params={"offset": offset},
            timeout=60
        )

        response.raise_for_status()

        data = response.json()
        jobs = data.get("content", [])

        print(f"  {len(jobs)} jobs | offset {offset}")

        for job in jobs:
            location = job.get("location")

            if isinstance(location, dict):
                country = str(location.get("country", "")).lower()

                if country == "sa":
                    saudi_jobs.append(job)

        if len(jobs) == 0:
            break

        offset += len(jobs)
        time.sleep(0.5)

    file_path = os.path.join(output_folder, f"{company}.json")

    with open(file_path, "w", encoding="utf-8") as f:
        json.dump(saudi_jobs, f, ensure_ascii=False, indent=2)

    print(f"Saudi jobs saved: {len(saudi_jobs)}")
    print(f"Saved: {file_path}")

print("Done!")
