# -*- coding: utf-8 -*-
"""Probe only. One request per location. No pulling."""
import os, sys, time, json, csv
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "pipeline"))  # repo/pipeline/
from ingestion.jooble import collector as jc
from common import config

CANDIDATES = [
    "Al Dhahran", "Medina", "Yanbu", "Al Ahsa", "Al Kharj",
    "Taif", "Abha", "Khamis Mushait", "Jizan", "Najran",
    "Hail", "Al Ula", "Umluj", "Rabigh", "Unaizah", "Arar",
]
GENERAL_BASELINE = 10000

def probe(loc):
    body = {"keywords": "", "location": loc, "page": 1}
    status, raw = jc.fetch_page(jc.API_KEYS[0], body)
    if status != 200:
        return status, None, 0, None, "http_error"
    obj = json.loads(raw)
    jobs = obj.get("jobs") or []
    tc = obj.get("totalCount")
    label = jobs[0].get("location") if jobs else None
    if len(jobs) == 0:
        verdict = "empty"
    elif tc is not None and tc >= GENERAL_BASELINE:
        verdict = "IGNORED"
    else:
        verdict = "pull"
    return status, tc, len(jobs), label, verdict

if __name__ == "__main__":
    out = os.path.join(config.CAP_DIR, "raw", "location_probe.csv")
    rows = []
    print("%-16s %5s %9s %5s %-9s %s" % ("query","http","total","rows","verdict","jooble_label"))
    for loc in CANDIDATES:
        s, tc, n, label, v = probe(loc)
        print("%-16s %5s %9s %5d %-9s %s" % (loc, s, tc, n, v, label))
        rows.append({"query_location": loc, "http": s, "total_count": tc,
                     "rows": n, "verdict": v, "jooble_label": label})
        time.sleep(12)
    with open(out, "w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print("")
    print("saved: " + out)
    print("estimated pull cost: %d requests"
          % sum((r["total_count"] or 0) // 20 + 1 for r in rows if r["verdict"] == "pull"))
