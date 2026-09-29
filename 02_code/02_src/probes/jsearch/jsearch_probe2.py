# -*- coding: utf-8 -*-
"""JSearch probe 2: depth ceiling by bisection + id stability on repeat."""
import json, time, urllib.parse, urllib.request, urllib.error
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
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return 0, str(e)

BASEQ = {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en", "num_pages": 1}

print("=== depth test ===")
for page in (3, 5, 10):
    p = dict(BASEQ); p["page"] = page
    s, raw = call(p)
    n = 0
    if s == 200:
        n = len(json.loads(raw).get("data") or [])
    print("page %2d  http=%s  rows=%d" % (page, s, n))
    time.sleep(5)

print("")
print("=== id stability: same query twice ===")
p = dict(BASEQ); p["page"] = 1
ids = []
for run in (1, 2):
    s, raw = call(p)
    if s != 200:
        print("run %d http=%s" % (run, s)); ids.append([]); time.sleep(5); continue
    d = json.loads(raw).get("data") or []
    ids.append([(j.get("job_uid"), j.get("job_title")) for j in d])
    print("run %d rows=%d" % (run, len(d)))
    time.sleep(5)

if ids[0] and ids[1]:
    u1 = {u for u, t in ids[0]}
    u2 = {u for u, t in ids[1]}
    print("uid overlap between identical runs: %d of %d" % (len(u1 & u2), len(u1)))
    t1 = {t for u, t in ids[0]}
    t2 = {t for u, t in ids[1]}
    print("title overlap between identical runs: %d of %d" % (len(t1 & t2), len(t1)))
