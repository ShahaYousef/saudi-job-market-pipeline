# -*- coding: utf-8 -*-
"""Jooble matrix runner. Consolidates the six original layer scripts
(l1, l1b, l1c, l1d, l2, l2b) behind one CLI argument:

    python matrix.py <l1|l1b|l1c|l1d|l2|l2b>

Each layer keeps its own original behaviour verbatim: none of these layers
enforced a break-based stopping rule while running (l2 and l2b only print a
mean yield informationally, after the full target list has run); only the
JSearch matrices below actually break out of a layer early. Preserved as-is.
"""
import os, sys, time, json, random
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
from ingestion.jooble import collector as jc
from common import state


def pages_in_last_batch(label):
    """Count pages for the most recent batch whose id contains `label`.
    Adapted for the ingest_date=YYYY-MM-DD partition layout: batch pages no
    longer live in their own directory, so this scans every partition for
    files whose <batch_id>__page_NNN.json prefix matches, then counts the
    most recent matching batch_id."""
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
# l1: one general query per city, sequential, shared seen_ids.
# ---------------------------------------------------------------------------
def run_l1():
    CITIES = ["Jeddah", "Dammam", "Jubail", "Khobar", "Mecca"]
    COOLDOWN_BETWEEN_QUERIES = 60

    summary = []
    for city in CITIES:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"keywords": "", "location": city}
        jc.QUERY_LABEL = "L1_city_" + city.replace(" ", "_")
        jc.BATCH_ID_OVERRIDE = ""

        print("")
        print("=" * 62)
        print("CITY = %s   (seen before: %d)" % (city, before))
        print("=" * 62)
        jc.run()

        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append((city, pages, gained, after, yld))
        print("CITY %s DONE  pages=%d  new_unique=%d  marginal_yield=%.2f"
              % (city, pages, gained, yld))

        if city != CITIES[-1]:
            print("cooldown %ds ..." % COOLDOWN_BETWEEN_QUERIES)
            time.sleep(COOLDOWN_BETWEEN_QUERIES)

    print("")
    print("=" * 62)
    print("MATRIX SUMMARY")
    print("%-10s %7s %12s %12s %10s" % ("city", "pages", "new_unique", "cumulative", "yield"))
    for c, p, g, a, y in summary:
        print("%-10s %7d %12d %12d %10.2f" % (c, p, g, a, y))
    print("=" * 62)


# ---------------------------------------------------------------------------
# l1b: region and new-city probes, with a pre-flight location guard.
# ---------------------------------------------------------------------------
def _l1b_preflight(loc):
    """One request. Returns (ok, total_count)."""
    GENERAL_BASELINE = 10000   # anything at or above this means the location was ignored
    body = {"keywords": "", "location": loc, "page": 1}
    status, raw = jc.fetch_page(jc.API_KEYS[0], body)
    if status != 200:
        print("  preflight http=%s, skipping" % status)
        return False, None
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError:
        print("  preflight returned non-JSON, skipping")
        return False, None
    tc = obj.get("totalCount")
    rows = len(obj.get("jobs") or [])
    print("  preflight: totalCount=%s rows=%d" % (tc, rows))
    if rows == 0:
        print("  -> zero results, location has no jobs. Skipping.")
        return False, tc
    if tc is not None and tc >= GENERAL_BASELINE:
        print("  -> LOCATION IGNORED by Jooble (fell back to general set). Skipping.")
        return False, tc
    return True, tc


def run_l1b():
    LOCATIONS = ["Al Qassim", "Buraydah", "NEOM"]
    COOLDOWN = 60

    summary = []
    for loc in LOCATIONS:
        print("")
        print("=" * 62)
        print("LOCATION = %s" % loc)
        print("=" * 62)
        ok, tc = _l1b_preflight(loc)
        time.sleep(10)
        if not ok:
            summary.append((loc, 0, 0, len(state.load_seen(jc.SEEN_PATH)), 0.0, "skipped"))
            continue

        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"keywords": "", "location": loc}
        jc.QUERY_LABEL = "L1_loc_" + loc.replace(" ", "_")
        jc.BATCH_ID_OVERRIDE = ""
        jc.run()

        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append((loc, pages, gained, after, yld, "ok"))
        print("LOCATION %s DONE  pages=%d  new_unique=%d  yield=%.2f"
              % (loc, pages, gained, yld))

        if loc != LOCATIONS[-1]:
            print("cooldown %ds ..." % COOLDOWN)
            time.sleep(COOLDOWN)

    print("")
    print("=" * 62)
    print("MATRIX SUMMARY")
    print("%-12s %6s %11s %11s %8s %9s" % ("location", "pages", "new_unique", "cumulative", "yield", "status"))
    for r in summary:
        print("%-12s %6d %11d %11d %8.2f %9s" % r)
    print("=" * 62)


# ---------------------------------------------------------------------------
# l1c: pull probed locations. Al Dhahran is depth-capped as a redundancy test.
# ---------------------------------------------------------------------------
def run_l1c():
    # (location, max_page). None = use default 50.
    TARGETS = [
        ("Al Dhahran",       5),   # label came back as Khobar, likely redundant. Test first.
        ("Medina",        None),
        ("Umluj",         None),
        ("Yanbu",         None),
        ("Jizan",         None),
        ("Abha",          None),
        ("Taif",          None),
        ("Rabigh",        None),
        ("Al Ahsa",       None),
        ("Al Ula",        None),
        ("Al Kharj",      None),
        ("Hail",          None),
        ("Khamis Mushait", None),
        ("Najran",        None),
        ("Unaizah",       None),
        ("Arar",          None),
    ]
    COOLDOWN = 45
    DEFAULT_MAX_PAGE = jc.MAX_PAGE

    summary = []
    for loc, cap in TARGETS:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"keywords": "", "location": loc}
        jc.QUERY_LABEL = "L1c_loc_" + loc.replace(" ", "_")
        jc.BATCH_ID_OVERRIDE = ""
        jc.MAX_PAGE = cap if cap else DEFAULT_MAX_PAGE

        print("")
        print("=" * 62)
        print("LOCATION = %s   (max_page=%d, seen before=%d)" % (loc, jc.MAX_PAGE, before))
        print("=" * 62)
        jc.run()

        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append((loc, pages, gained, after, yld))
        print("DONE %s  pages=%d  new_unique=%d  yield=%.2f" % (loc, pages, gained, yld))

        if loc != TARGETS[-1][0]:
            time.sleep(COOLDOWN)

    jc.MAX_PAGE = DEFAULT_MAX_PAGE
    print("")
    print("=" * 62)
    print("MATRIX SUMMARY")
    print("%-16s %6s %11s %11s %8s" % ("location", "pages", "new_unique", "cumulative", "yield"))
    for r in summary:
        print("%-16s %6d %11d %11d %8.2f" % r)
    print("=" * 62)


# ---------------------------------------------------------------------------
# l1d: locations that were probed or referenced but never pulled.
# ---------------------------------------------------------------------------
def run_l1d():
    TARGETS = ["Riyadh", "Tabuk", "Buraidah"]
    COOLDOWN = 45

    summary = []
    for loc in TARGETS:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"keywords": "", "location": loc}
        jc.QUERY_LABEL = "L1d_loc_" + loc.replace(" ", "_")
        jc.BATCH_ID_OVERRIDE = ""
        print("")
        print("=" * 62)
        print("LOCATION = %s   (seen before=%d)" % (loc, before))
        print("=" * 62)
        jc.run()
        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append((loc, pages, gained, after, yld))
        print("DONE %s  pages=%d  new_unique=%d  yield=%.2f" % (loc, pages, gained, yld))
        if loc != TARGETS[-1]:
            time.sleep(COOLDOWN)

    print("")
    print("=" * 62)
    print("%-12s %6s %11s %11s %8s" % ("location", "pages", "new_unique", "cumulative", "yield"))
    for r in summary:
        print("%-12s %6d %11d %11d %8.2f" % r)
    print("=" * 62)


# ---------------------------------------------------------------------------
# l2: exhaustible keywords within Riyadh. No randomisation. Informational
# last-5 mean printed only after the full list has run (no early break).
# ---------------------------------------------------------------------------
def run_l2():
    LOCATION = "Riyadh"
    KEYWORDS = [
        "procurement", "commissioning", "representative", "architect", "technician",
        "driver", "analyst", "inspector", "hvac", "chef",
        "cleaner", "electrician", "nurse", "welder", "foreman",
        "instructor", "receptionist", "pharmacist",
    ]
    COOLDOWN = 30

    summary = []
    for kw in KEYWORDS:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"keywords": kw, "location": LOCATION}
        jc.QUERY_LABEL = "L2_kw_" + kw
        jc.BATCH_ID_OVERRIDE = ""
        print("")
        print("=" * 62)
        print("KEYWORD = %s in %s   (seen before=%d)" % (kw, LOCATION, before))
        print("=" * 62)
        jc.run()
        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        summary.append((kw, pages, gained, after, yld))
        print("DONE %s  pages=%d  new_unique=%d  yield=%.2f" % (kw, pages, gained, yld))
        if kw != KEYWORDS[-1]:
            time.sleep(COOLDOWN)

    print("")
    print("=" * 62)
    print("%-16s %6s %11s %11s %8s" % ("keyword", "pages", "new_unique", "cumulative", "yield"))
    for r in summary:
        print("%-16s %6d %11d %11d %8.2f" % r)
    last5 = [r[4] for r in summary[-5:]]
    print("last-5 mean yield: %.2f   (stop threshold = 2.00)" % (sum(last5) / len(last5)))
    print("=" * 62)


# ---------------------------------------------------------------------------
# l2b: capped keywords in Riyadh. Randomised order, fixed seed. Mean of ALL
# yields printed (not last-5), informational only, no early break.
# ---------------------------------------------------------------------------
def run_l2b():
    LOCATION = "Riyadh"
    # randomised order: the stopping rule must not be biased by size ordering
    KEYWORDS = ["operator", "developer", "designer", "controller", "consultant", "accountant"]
    random.seed(42)
    random.shuffle(KEYWORDS)
    COOLDOWN = 30

    print("run order: " + ", ".join(KEYWORDS))
    summary = []
    for kw in KEYWORDS:
        before = len(state.load_seen(jc.SEEN_PATH))
        jc.QUERY = {"keywords": kw, "location": LOCATION}
        jc.QUERY_LABEL = "L2b_kw_" + kw
        jc.BATCH_ID_OVERRIDE = ""
        print("")
        print("=" * 62)
        print("KEYWORD = %s in %s   (seen before=%d)" % (kw, LOCATION, before))
        print("=" * 62)
        jc.run()
        after = len(state.load_seen(jc.SEEN_PATH))
        pages = pages_in_last_batch(jc.QUERY_LABEL)
        gained = after - before
        yld = (gained / pages) if pages else 0
        trunc = "YES" if pages >= jc.MAX_PAGE else "no"
        summary.append((kw, pages, gained, after, yld, trunc))
        print("DONE %s  pages=%d  new_unique=%d  yield=%.2f  truncated=%s"
              % (kw, pages, gained, yld, trunc))
        if kw != KEYWORDS[-1]:
            time.sleep(COOLDOWN)

    print("")
    print("=" * 62)
    print("%-14s %6s %11s %11s %8s %10s" % ("keyword", "pages", "new_unique", "cumulative", "yield", "truncated"))
    for r in summary:
        print("%-14s %6d %11d %11d %8.2f %10s" % r)
    ys = [r[4] for r in summary]
    print("mean yield this layer: %.2f   (stop threshold = 2.00)" % (sum(ys) / len(ys)))
    print("=" * 62)


LAYERS = {
    "l1": run_l1,
    "l1b": run_l1b,
    "l1c": run_l1c,
    "l1d": run_l1d,
    "l2": run_l2,
    "l2b": run_l2b,
}

if __name__ == "__main__":
    if len(sys.argv) != 2 or sys.argv[1] not in LAYERS:
        sys.exit("Usage: python matrix.py <%s>" % "|".join(LAYERS))
    LAYERS[sys.argv[1]]()
