# -*- coding: utf-8 -*-
"""Follow the search-v2 cursor and measure depth, novelty and failure rate."""
import json, time, urllib.parse, urllib.request, urllib.error, sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from ingestion.jsearch import collector as jc
from common import state

BASE = "https://api.openwebninja.com/jsearch/search-v2"
MAX_STEPS = 10

def call(params):
    req = urllib.request.Request(BASE + "?" + urllib.parse.urlencode(params),
                                 headers={"x-api-key": jc.API_KEYS[0]})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return 0, str(e)

seen = state.load_seen(jc.SEEN_PATH)
print("baseline seen ids: %d" % len(seen))
batch = set()
cursor = None

for step in range(1, MAX_STEPS + 1):
    p = {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en"}
    if cursor:
        p["cursor"] = cursor
    s, raw = call(p)
    if s != 200:
        print("step %2d  http=%s  %s" % (step, s, raw[:120]))
        time.sleep(10); continue
    o = json.loads(raw)
    d = o.get("data") or {}
    jobs = d.get("jobs") or []
    nxt = d.get("cursor")
    new_global = sum(1 for j in jobs if j.get("job_uid") not in seen)
    dup_batch  = sum(1 for j in jobs if j.get("job_uid") in batch)
    for j in jobs:
        seen.add(j.get("job_uid")); batch.add(j.get("job_uid"))
    print("step %2d  rows=%2d  new_vs_corpus=%2d  dup_within_batch=%2d  cum_batch=%3d  cursor=%s"
          % (step, len(jobs), new_global, dup_batch, len(batch), "yes" if nxt else "NONE"))
    if not nxt:
        print("cursor exhausted at step %d" % step)
        break
    if not jobs:
        print("empty page at step %d" % step)
        break
    cursor = nxt
    time.sleep(8)

print("")
print("distinct records from this single query via cursor: %d" % len(batch))
print("compare: /search page-based gave 111 for the same query")
