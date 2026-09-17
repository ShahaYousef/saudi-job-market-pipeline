# -*- coding: utf-8 -*-
"""JSearch expansion probe: date_posted axis, phrasing axis, and search-v2 cursor."""
import json, time, urllib.parse, urllib.request, urllib.error, sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from ingestion.jsearch import collector as jc
from common import state

seen = state.load_seen(jc.SEEN_PATH)
print("baseline seen ids: %d" % len(seen))
print("")

def novelty(d):
    return sum(1 for j in d if j.get("job_uid") not in seen)

print("=== axis 1: date_posted partitions (same query) ===")
for dp in ["today", "3days", "week", "month"]:
    p = {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en",
         "page": 1, "num_pages": 1, "date_posted": dp}
    s, raw, att = jc.fetch_with_retry(jc.API_KEYS[0], p)
    if s != 200:
        print("%-8s http=%s" % (dp, s)); time.sleep(8); continue
    d = json.loads(raw).get("data") or []
    print("%-8s rows=%2d  new=%2d  novelty=%d%%" %
          (dp, len(d), novelty(d), round(100*novelty(d)/len(d)) if d else 0))
    time.sleep(8)

print("")
print("=== axis 2: alternative general phrasings ===")
for q in ["vacancies in Saudi Arabia", "careers in Saudi Arabia", "hiring in Saudi Arabia"]:
    p = {"query": q, "country": "sa", "language": "en", "page": 1, "num_pages": 1}
    s, raw, att = jc.fetch_with_retry(jc.API_KEYS[0], p)
    if s != 200:
        print("%-28s http=%s" % (q, s)); time.sleep(8); continue
    d = json.loads(raw).get("data") or []
    print("%-28s rows=%2d  new=%2d  novelty=%d%%" %
          (q, len(d), novelty(d), round(100*novelty(d)/len(d)) if d else 0))
    time.sleep(8)

print("")
print("=== axis 3: search-v2 cursor endpoint (never tested) ===")
qs = urllib.parse.urlencode({"query": "jobs in Saudi Arabia", "country": "sa", "language": "en"})
url = "https://api.openwebninja.com/jsearch/search-v2?" + qs
req = urllib.request.Request(url, headers={"x-api-key": jc.API_KEYS[0]})
try:
    with urllib.request.urlopen(req, timeout=90) as r:
        s, raw = r.status, r.read().decode("utf-8")
except urllib.error.HTTPError as e:
    s, raw = e.code, e.read().decode("utf-8", errors="replace")
except Exception as e:
    s, raw = 0, str(e)
print("http=%s" % s)
if s == 200:
    o = json.loads(raw)
    print("top-level keys: " + ", ".join(o.keys()))
    d = o.get("data") or []
    print("rows=%d  new=%d" % (len(d), novelty(d)))
    for k in ("cursor", "next_cursor", "next_page_token", "pagination"):
        if k in o: print("PAGINATION FIELD FOUND: %s = %s" % (k, str(o[k])[:80]))
else:
    print(raw[:300])
