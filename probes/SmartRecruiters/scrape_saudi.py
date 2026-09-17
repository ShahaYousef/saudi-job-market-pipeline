import json

with open("saudi_jobs.json", "r", encoding="utf-8") as f:
    jobs = json.load(f)

saudi_jobs = [
    job for job in jobs
    if job.get("country", "").lower() == "sa"
]

with open("saudi_jobs_only.json", "w", encoding="utf-8") as f:
    json.dump(saudi_jobs, f, ensure_ascii=False, indent=2)

print(f"عدد وظائف السعودية: {len(saudi_jobs)}")
print("Saved as: saudi_jobs_only.json")
