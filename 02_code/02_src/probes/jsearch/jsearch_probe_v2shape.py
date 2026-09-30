# -*- coding: utf-8 -*-
"""Inspect the actual shape of search-v2 response."""
import json, urllib.parse, urllib.request, urllib.error, sys, os
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from ingestion.jsearch import collector as jc
from common import config

OUT_DIR = os.path.join(config.RAW_DIR, "probes")   # outside the repository, like the other raw files
os.makedirs(OUT_DIR, exist_ok=True)

qs = urllib.parse.urlencode({"query": "jobs in Saudi Arabia", "country": "sa", "language": "en"})
url = "https://api.openwebninja.com/jsearch/search-v2?" + qs
req = urllib.request.Request(url, headers={"x-api-key": jc.API_KEYS[0]})
try:
    with urllib.request.urlopen(req, timeout=90) as r:
        s, raw = r.status, r.read().decode("utf-8")
except urllib.error.HTTPError as e:
    s, raw = e.code, e.read().decode("utf-8", errors="replace")

open(os.path.join(OUT_DIR, "jsearch_v2_shape.json"),
     "w", encoding="utf-8").write(raw)
print("http=%s  bytes=%d" % (s, len(raw)))
o = json.loads(raw)
print("top keys: " + ", ".join(o.keys()))
print("parameters echoed: " + json.dumps(o.get("parameters"), ensure_ascii=False))
d = o.get("data")
print("type(data) = %s" % type(d).__name__)
if isinstance(d, dict):
    print("data keys: " + ", ".join(d.keys()))
    for k, v in d.items():
        print("  %s -> %s (len %s)" % (k, type(v).__name__, len(v) if hasattr(v,'__len__') else 'n/a'))
elif isinstance(d, list):
    print("len(data) = %d" % len(d))
    print("type of first element: %s" % type(d[0]).__name__)
    print("first element (first 400 chars):")
    print(str(d[0])[:400])
