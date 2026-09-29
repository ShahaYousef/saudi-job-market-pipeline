# -*- coding: utf-8 -*-
"""Does query phrasing change the result size? Four phrasings, one keyword."""
import json, time, urllib.parse, urllib.request, urllib.error
import sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from ingestion.jsearch import collector as jc

VARIANTS = [
    "architect jobs in Riyadh",
    "architect Riyadh",
    "architect",
    "architect in Saudi Arabia",
]

for q in VARIANTS:
    params = {"query": q, "country": "sa", "language": "en", "page": 1, "num_pages": 1}
    s, raw, att = jc.fetch_with_retry(jc.API_KEYS[0], params)
    if s != 200:
        print("%-28s http=%s" % (q, s)); time.sleep(8); continue
    d = json.loads(raw).get("data") or []
    hit = sum(1 for j in d if "architect" in (j.get("job_title") or "").lower())
    cities = [j.get("job_city") for j in d[:4]]
    print("%-28s rows=%2d  title_match=%d  cities=%s" % (q, len(d), hit, cities))
    time.sleep(8)
