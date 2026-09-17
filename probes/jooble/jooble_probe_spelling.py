# -*- coding: utf-8 -*-
"""Spelling probe only. One request per variant, no full pull."""
import os, sys, time, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from ingestion.jooble import collector as jc

VARIANTS = ["Buraidah", "Burayda", "Neom", "Tabuk"]

def probe(loc):
    body = {"keywords": "", "location": loc, "page": 1}
    status, raw = jc.fetch_page(jc.API_KEYS[0], body)
    if status != 200:
        return status, None, 0, None
    obj = json.loads(raw)
    jobs = obj.get("jobs") or []
    sample = jobs[0].get("location") if jobs else None
    return status, obj.get("totalCount"), len(jobs), sample

if __name__ == "__main__":
    print("%-12s %6s %11s %6s  %s" % ("variant","http","totalCount","rows","first result location"))
    for v in VARIANTS:
        s, tc, n, loc1 = probe(v)
        print("%-12s %6s %11s %6d  %s" % (v, s, tc, n, loc1))
        time.sleep(12)
