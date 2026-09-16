# -*- coding: utf-8 -*-
"""JSearch matrix runner. Consolidates the three original matrix scripts
(jsearch_matrix.py, jsearch_matrix_kw.py, jsearch_matrix_temporal.py) behind
one CLI argument:

    python jsearch_matrix.py <coverage|kw|temporal>

IMPORTANT behavioural difference preserved between layers: "coverage" runs
city queries then keyword queries as ONE continuous sequence with a SINGLE
stopping-rule window (last 5 queries across both axes combined) exactly as
the original jsearch_matrix.py did -- it does not reset the window at the
city/keyword boundary. "kw" and "temporal" are each their own independent
axis with their own independent stopping-rule window, exactly as the
original jsearch_matrix_kw.py and jsearch_matrix_temporal.py did.
"""
import os, sys, time, random
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # repo/
from src.collectors import jsearch as jc
from src.common import state


def pages_in_last_batch(label):
    """Count pages for the most recent batch whose id contains `label`.
    Adapted for the ingest_date=YYYY-MM-DD partition layout: scans every
    partition for <batch_id>__page_NNN.json files matching the label, then
    counts the most recent matching batch_id."""
    base = jc.RAW_DIR
    if not os.path.isdir(base):
        return 0
    batch_ids = set()
    for d in os.listdir(base):
        part_dir = os.path.join(base, d)
        if not os.path.isdir(part_dir):
            continue
        for f in os.listdir(part_dir):
            if f.endswith(".json") and "__page_" in f:
                bid = f.rsplit("__page_", 1)[0]
                if label in bid:
                    batch_ids.add(bid)
    if not batch_ids:
        return 0
    latest = sorted(batch_ids)[-1]
    count = 0
    for d in os.listdir(base):
        part_dir = os.path.join(base, d)
        if not os.path.isdir(part_dir):
            continue
        count += len([f for f in os.listdir(part_dir)
                      if f.startswith(latest + "__page_") and f.endswith(".json")])
    return count


# ---------------------------------------------------------------------------
# coverage: geography then job title, ONE combined sequence, ONE stopping
# window spanning both axes. No date_posted filter: this matrix maximises
# coverage, freshness is the daily monitor's job.
# ---------------------------------------------------------------------------
def run_coverage():
    # Layer A: geography. Derived from the Jooble city distribution, largest markets first.
    CITIES = ["Riyadh", "Jeddah", "Dammam", "Khobar", "Mecca",
              "Medina", "Jubail", "Tabuk", "Abha", "Al Khobar Eastern Province"]

    # Layer B: job titles within Riyadh. Same list that performed on Jooble.
    RIYADH_KEYWORDS = ["accountant", "technician", "sales", "engineer", "nurse",
                       "driver", "developer", "designer", "operator", "consultant",
                       "teacher", "chef", "analyst", "architect", "procurement"]
    random.seed(42)
    random.shuffle(RIYADH_KEYWORDS)

    COOLDOWN = 20

    matrix = [("A_city_" + c.replace(" ", "_"), "jobs in " + c) for c in CITIES]
    matrix += [("B_kw_" + k, k + " jobs in Riyadh") for k in RIYADH_KEYWORDS]

    print("matrix size: %d queries" % len(matrix))
    summary = []
    for label, q in matrix:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"query": q, "country": "sa", "language": "en", "num_pages": 1}
        jc.QUERY_LABEL = label
        jc.BATCH_ID_OVERRIDE = ""
        print("")
        print("=" * 64)
        print("QUERY = %s   (seen before=%d)" % (q, before))
        print("=" * 64)
        jc.run()
        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(label)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append((label, pages, gained, after, yld))
        print("DONE %s  pages=%d  new_unique=%d  yield=%.2f" % (label, pages, gained, yld))
        if len(summary) >= 5:
            last5 = sum(r[4] for r in summary[-5:]) / 5
            if last5 < 2.0:
                print("")
                print("STOPPING RULE MET: last-5 mean yield %.2f < 2.00" % last5)
                break
        if (label, q) != matrix[-1]:
            time.sleep(COOLDOWN)

    print("")
    print("=" * 64)
    print("%-28s %6s %11s %11s %8s" % ("query", "pages", "new_unique", "cumulative", "yield"))
    for r in summary:
        print("%-28s %6d %11d %11d %8.2f" % r)
    print("=" * 64)


# ---------------------------------------------------------------------------
# kw: keyword axis on its own, independent stopping-rule window.
# ---------------------------------------------------------------------------
def run_kw():
    KEYWORDS = ["accountant", "technician", "sales", "engineer", "nurse",
                "driver", "developer", "designer", "operator", "consultant",
                "teacher", "chef", "analyst", "architect", "procurement"]
    random.seed(42)
    random.shuffle(KEYWORDS)
    COOLDOWN = 20

    print("keyword axis, run order: " + ", ".join(KEYWORDS))
    summary = []
    for kw in KEYWORDS:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"query": kw + " jobs in Riyadh", "country": "sa",
                    "language": "en", "num_pages": 1}
        jc.QUERY_LABEL = "B_kw_" + kw
        jc.BATCH_ID_OVERRIDE = ""
        print("")
        print("=" * 64)
        print("KEYWORD = %s   (seen before=%d)" % (kw, before))
        print("=" * 64)
        jc.run()
        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append((kw, pages, gained, after, yld))
        print("DONE %s  pages=%d  new_unique=%d  yield=%.2f" % (kw, pages, gained, yld))

        if len(summary) >= 5:
            last5 = sum(r[4] for r in summary[-5:]) / 5
            print("  last-5 mean yield on this axis: %.2f" % last5)
            if last5 < 2.0:
                print("")
                print("STOPPING RULE MET on keyword axis: %.2f < 2.00" % last5)
                break
        if kw != KEYWORDS[-1]:
            time.sleep(COOLDOWN)

    print("")
    print("=" * 64)
    print("%-16s %6s %11s %11s %8s" % ("keyword", "pages", "new_unique", "cumulative", "yield"))
    for r in summary:
        print("%-16s %6d %11d %11d %8.2f" % r)
    print("=" * 64)


# ---------------------------------------------------------------------------
# temporal: date_posted is the only axis that measured 100% novelty. Crossed
# with the top geographies. Own independent stopping-rule window.
# ---------------------------------------------------------------------------
def run_temporal():
    DATES = ["today", "3days", "week", "month"]
    GEOS  = ["Saudi Arabia", "Riyadh", "Jeddah", "Dammam"]

    MATRIX = [(dp, g) for g in GEOS for dp in DATES]
    random.seed(42)
    random.shuffle(MATRIX)
    COOLDOWN = 15

    print("temporal matrix: %d queries" % len(MATRIX))
    summary = []
    for dp, geo in MATRIX:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"query": "jobs in " + geo, "country": "sa",
                    "language": "en", "num_pages": 1, "date_posted": dp}
        jc.QUERY_LABEL = "C_%s_%s" % (dp, geo.replace(" ", "_"))
        jc.BATCH_ID_OVERRIDE = ""
        print("")
        print("=" * 64)
        print("date_posted=%s  geo=%s   (seen before=%d)" % (dp, geo, before))
        print("=" * 64)
        jc.run()
        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append(("%s|%s" % (dp, geo), pages, gained, after, yld))
        print("DONE  pages=%d  new_unique=%d  yield=%.2f" % (pages, gained, yld))

        if len(summary) >= 5:
            last5 = sum(r[4] for r in summary[-5:]) / 5
            print("  last-5 mean yield: %.2f" % last5)
            if last5 < 2.0:
                print("")
                print("STOPPING RULE MET on temporal axis: %.2f < 2.00" % last5)
                break
        time.sleep(COOLDOWN)

    print("")
    print("=" * 64)
    print("%-26s %6s %11s %11s %8s" % ("date|geo", "pages", "new_unique", "cumulative", "yield"))
    for r in summary:
        print("%-26s %6d %11d %11d %8.2f" % r)
    print("=" * 64)


LAYERS = {
    "coverage": run_coverage,
    "kw": run_kw,
    "temporal": run_temporal,
}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in LAYERS:
        sys.exit("Usage: python jsearch_matrix.py <%s>" % "|".join(LAYERS))
    LAYERS[sys.argv[1]]()
