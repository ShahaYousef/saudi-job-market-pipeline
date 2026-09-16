# -*- coding: utf-8 -*-
"""JSearch probe 3: is 504 a ceiling or transient? And do pages return distinct records?"""
import json, time, urllib.parse, urllib.request, urllib.error
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # repo/
from src.common import config

API_KEY = config.jsearch_api_keys()[0]
BASE = "https://api.openwebninja.com/jsearch/search"

def call(params):
    qs = "&".join("%s=%s" % (k, urllib.parse.quote(str(v))) for k, v in params.items())
    req = urllib.request.Request(BASE + "?" + qs, headers={"x-api-key": API_KEY})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return 0, str(e)

BASEQ = {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en", "num_pages": 1}

print("=== is page 10 deterministic? three attempts ===")
for attempt in (1, 2, 3):
    p = dict(BASEQ); p["page"] = 10
    s, raw = call(p)
    n = len(json.loads(raw).get("data") or []) if s == 200 else 0
    print("attempt %d  http=%s  rows=%d" % (attempt, s, n))
    time.sleep(8)

print("")
print("=== sequential pages 1..8, cumulative distinct uids ===")
seen = set()
for page in range(1, 9):
    p = dict(BASEQ); p["page"] = page
    s, raw = call(p)
    if s != 200:
        print("page %d  http=%s" % (page, s))
        time.sleep(8); continue
    d = json.loads(raw).get("data") or []
    new = sum(1 for j in d if j.get("job_uid") not in seen)
    for j in d: seen.add(j.get("job_uid"))
    print("page %d  rows=%2d  new=%2d  cumulative=%d" % (page, len(d), new, len(seen)))
    time.sleep(8)
print("total distinct across pages 1-8: %d" % len(seen))
