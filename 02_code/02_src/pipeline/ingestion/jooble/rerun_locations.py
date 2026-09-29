# pipeline/ingestion/jooble/rerun_locations.py
"""Re-runs chosen locations of a Jooble matrix layer, with the same query label the layer uses,
so a layer that stopped midway (timeout, exhausted key) can be finished without repeating the
locations that already landed.

    py pipeline/ingestion/jooble/rerun_locations.py L1c_loc_ Hail "Khamis Mushait" Najran Unaizah Arar

First argument: the layer's label prefix (l1 / l1b: L1_loc_, l1c: L1c_loc_; see matrix.py).
Every landed page is logged like a normal run; nothing already landed is changed.
"""
import sys, time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # pipeline/
from ingestion.jooble import collector as jc

COOLDOWN = 45

if len(sys.argv) < 3:
    sys.exit('Usage: rerun_locations.py <label_prefix> <location> [<location> ...]')

prefix, locations = sys.argv[1], sys.argv[2:]
for i, loc in enumerate(locations):
    jc.QUERY = {"keywords": "", "location": loc}
    jc.QUERY_LABEL = prefix + loc.replace(" ", "_")
    jc.BATCH_ID_OVERRIDE = ""
    print("")
    print("=" * 62)
    print("LOCATION = %s   (label %s)" % (loc, jc.QUERY_LABEL))
    print("=" * 62)
    jc.run()
    if i < len(locations) - 1:
        time.sleep(COOLDOWN)