# -*- coding: utf-8 -*-
"""Probe keywords inside Riyadh. One request each, no pulling."""
import os, sys, time, json, csv
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from ingestion.jooble import collector as jc
from common import config

LOCATION = "Riyadh"
RIYADH_BASELINE = 5000   # near this means the keyword was ignored
CEILING = 1000

KEYWORDS = [
    "technician", "inspector", "accountant", "chef", "operator",
    "driver", "electrician", "architect", "designer", "foreman",
    "cleaner", "instructor", "controller", "analyst", "consultant",
    "representative", "developer", "commissioning", "hvac", "procurement",
    "welder", "nurse", "pharmacist", "receptionist",
]

def probe(kw):
    body = {"keywords": kw, "location": LOCATION, "page": 1}
    status, raw = jc.fetch_page(jc.API_KEYS[0], body)
    if status != 200:
        return status, None, 0, "http_error", 0
    obj = json.loads(raw)
    jobs = obj.get("jobs") or []
    tc = obj.get("totalCount")
    hit = sum(1 for j in jobs if kw.lower() in (j.get("title") or "").lower())
    if len(jobs) == 0:
        v = "empty"
    elif tc is not None and tc >= RIYADH_BASELINE:
        v = "IGNORED"
    elif tc is not None and tc > CEILING:
        v = "capped"
    else:
        v = "pull"
    return status, tc, len(jobs), v, hit

if __name__ == "__main__":
    out = os.path.join(config.CAP_DIR, "raw", "keyword_probe_riyadh.csv")
    rows, cost = [], 0
    print("%-16s %5s %8s %5s %-8s %s" % ("keyword","http","total","rows","verdict","title_match"))
    for kw in KEYWORDS:
        s, tc, n, v, hit = probe(kw)
        print("%-16s %5s %8s %5d %-8s %d/%d" % (kw, s, tc, n, v, hit, n))
        rows.append({"keyword": kw, "location": LOCATION, "http": s,
                     "total_count": tc, "rows": n, "verdict": v,
                     "title_match": hit})
        if v == "pull":
            cost += (tc // 20) + 1
        elif v == "capped":
            cost += 50
        time.sleep(12)
    with open(out, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader(); w.writerows(rows)
    print("")
    print("saved: " + out)
    print("estimated pull cost: %d requests" % cost)
