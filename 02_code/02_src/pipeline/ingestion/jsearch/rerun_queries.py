# pipeline/ingestion/jsearch/rerun_queries.py
# -*- coding: utf-8 -*-
"""Re-run named JSearch matrix queries, without the stopping rule.

Used when a campaign was cut short (quota) and only some labels are missing.
Each label is rebuilt with exactly the same query as matrix.py, so the rows
count as the same baseline query. The seen file is NOT reset.

    py pipeline/ingestion/jsearch/rerun_queries.py <label> [<label> ...]
    py pipeline/ingestion/jsearch/rerun_queries.py --dry-run <label> ...

Label formats (same as matrix.py):
    A_city_<City>              e.g. A_city_Medina, A_city_Al_Khobar_Eastern_Province
    B_kw_<keyword>             e.g. B_kw_architect   (always "... jobs in Riyadh")
    C_<window>_<Geo>           e.g. C_week_Saudi_Arabia  (window: today|3days|week|month)
"""
import sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
from ingestion.jsearch import collector as jc

COOLDOWN = 20
QUOTA = (401, 403, 429)
_last = {"status": None}
_orig_fetch = jc.fetch_with_retry


def _fetch_and_remember(key, params):
    s, raw, attempts = _orig_fetch(key, params)
    _last["status"] = s
    return s, raw, attempts


jc.fetch_with_retry = _fetch_and_remember   # lets us stop the whole run when all keys are spent
WINDOWS = ("today", "3days", "week", "month")


def query_for(label):
    base = {"country": "sa", "language": "en", "num_pages": 1}
    if label.startswith("A_city_"):
        city = label[len("A_city_"):].replace("_", " ")
        return dict(base, query="jobs in " + city)
    if label.startswith("B_kw_"):
        kw = label[len("B_kw_"):]
        return dict(base, query=kw + " jobs in Riyadh")
    if label.startswith("C_"):
        window, _, geo = label[2:].partition("_")
        if window not in WINDOWS or not geo:
            raise ValueError("bad temporal label: " + label)
        return dict(base, query="jobs in " + geo.replace("_", " "), date_posted=window)
    raise ValueError("unknown label format: " + label)


def main(args):
    dry = "--dry-run" in args
    labels = [a for a in args if a != "--dry-run"]
    if not labels:
        sys.exit(__doc__)
    plan = [(lb, query_for(lb)) for lb in labels]   # fail fast on a bad label
    for lb, q in plan:
        print("%-36s %s" % (lb, q))
    if dry:
        return
    print("keys loaded: %d (the first key is tried first)" % len(jc.API_KEYS))
    for i, (lb, q) in enumerate(plan):
        jc.QUERY = q
        jc.QUERY_LABEL = lb
        jc.BATCH_ID_OVERRIDE = ""
        print("")
        print("=" * 64)
        print("LABEL = %s   QUERY = %s" % (lb, q))
        print("=" * 64)
        jc.run()
        if _last["status"] in QUOTA:
            rest = [lb2 for lb2, _ in plan[i:]]
            print("")
            print("ALL KEYS EXHAUSTED. Not run (or cut short): " + " ".join(rest))
            return
        if i < len(plan) - 1:
            time.sleep(COOLDOWN)


if __name__ == "__main__":
    main(sys.argv[1:])
