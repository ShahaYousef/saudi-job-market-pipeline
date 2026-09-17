# -*- coding: utf-8 -*-
"""JSearch probe. 4 requests. Resolves pagination, date fields, country filter, id stability."""
import json, urllib.request, urllib.error, time, collections
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from common import config

API_KEY = config.jsearch_api_keys()[0]
BASE = "https://api.openwebninja.com/jsearch/search"

def call(params):
    qs = "&".join("%s=%s" % (k, urllib.parse.quote(str(v))) for k, v in params.items())
    req = urllib.request.Request(BASE + "?" + qs, headers={"x-api-key": API_KEY})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")

import urllib.parse

PROBES = [
    ("A_en_page1",  {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en", "page": 1,  "num_pages": 1}),
    ("B_en_page2",  {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en", "page": 2,  "num_pages": 1}),
    ("C_en_page20", {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en", "page": 20, "num_pages": 1}),
    ("D_week",      {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en", "page": 1,  "num_pages": 1, "date_posted": "week"}),
]

seen = {}
for name, p in PROBES:
    print("-" * 58)
    print("PROBE " + name + "   " + json.dumps(p, ensure_ascii=False))
    s, raw = call(p)
    open(r"C:\Users\admin\Desktop\Data Engineering Bootcamp\capstone\verification\payloads\jsearch_probe_%s.json" % name,
         "w", encoding="utf-8").write(raw)
    print("http: %s" % s)
    if s != 200:
        print(raw[:300]); time.sleep(3); continue
    o = json.loads(raw)
    d = o.get("data") or []
    print("rows: %d" % len(d))
    print("top-level keys: " + ", ".join(o.keys()))
    if not d:
        time.sleep(3); continue
    utc  = sum(1 for j in d if j.get("job_posted_at_datetime_utc"))
    ts   = sum(1 for j in d if j.get("job_posted_at_timestamp"))
    rel  = sum(1 for j in d if j.get("job_posted_at"))
    print("date fill  utc=%d/%d  timestamp=%d/%d  relative=%d/%d" % (utc,len(d),ts,len(d),rel,len(d)))
    print("sample utc value : %s" % (d[0].get("job_posted_at_datetime_utc")))
    print("sample relative  : %s" % (d[0].get("job_posted_at")))
    ctry = collections.Counter(j.get("job_country") for j in d)
    city = collections.Counter(j.get("job_city") for j in d)
    print("countries: %s" % dict(ctry))
    print("cities   : %s" % dict(city.most_common(5)))
    dup = sum(1 for j in d if j.get("job_uid") in seen)
    for j in d: seen[j.get("job_uid")] = name
    print("uid overlap with earlier probes: %d" % dup)
    print("uid len=%d  id len=%d" % (len(d[0].get("job_uid") or ""), len(d[0].get("job_id") or "")))
    time.sleep(3)

print("-" * 58)
print("total distinct uids across probes: %d" % len(seen))
