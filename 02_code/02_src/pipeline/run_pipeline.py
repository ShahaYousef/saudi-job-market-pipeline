# pipeline/run_pipeline.py
# -*- coding: utf-8 -*-
"""One command for the whole pipeline: extract -> land in ADLS -> COPY INTO RAW -> dbt -> export to ADLS.

Steps, in order. Each one stops the run when it fails (policy: dbt/DATA_QUALITY.md):

    extract    the extraction script of each selected source
    upload     pipeline/landing/upload_to_adls.py            (new files only, never overwrites)
    load       dbt run-operation load_raw                     (COPY INTO RAW, new files only)
    freshness  dbt source freshness                           (warnings print; errors stop the run)
    build      dbt build                                      (seeds, models and every test)
    export     dbt run-operation export_marts                 (MARTS -> ADLS curated/, Parquet)

By default only the four ATS boards are extracted. Jooble and JSearch are query campaigns with
request quotas (Jooble: 500 requests per key, lifetime), so they are extracted only when named
with --sources, which runs their default collector query. Upload, load and build always cover all
six sources, so files already landed from earlier campaigns are still loaded and rebuilt.

Run from 02_code/02_src, after `pip install -r ../requirements.txt`, with 02_code/.env filled in
and a working dbt profile (`py -m dbt.cli.main debug` passes in dbt/):

    py pipeline/run_pipeline.py                                   # everything, ATS sources
    py pipeline/run_pipeline.py --steps load freshness build      # reload and rebuild only
    py pipeline/run_pipeline.py --sources ashby workable jsearch  # choose what to extract
    py pipeline/run_pipeline.py --dry-run                         # print the plan, run nothing

Every run gets a run_id (PIPELINE_RUN_ID, also written to extract_log.csv by the ATS scripts)
and one summary row in <raw>/run_log.csv.
"""
import argparse
import csv
import os
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parents[1]      # 02_code/02_src: every script path below is relative to it
DBT_DIR = SRC_DIR / "dbt"
sys.path.insert(0, str(SRC_DIR / "pipeline"))
from common import config  # noqa: E402

EXTRACTORS = {
    "ashby":           ["pipeline/ingestion/ashby/ashby.py"],
    "workable":        ["pipeline/ingestion/workable/workable.py"],
    "greenhouse":      ["pipeline/ingestion/greenhouse/greenhouse.py"],
    "smartrecruiters": ["pipeline/ingestion/smartrecruiters/smartrecruiters.py"],
    "jooble":          ["pipeline/ingestion/jooble/collector.py"],    # one query, up to 50 pages
    "jsearch":         ["pipeline/ingestion/jsearch/collector.py"],   # one query, up to 20 pages
}
ATS_SOURCES = ["ashby", "workable", "greenhouse", "smartrecruiters"]
ALL_STEPS = ["extract", "upload", "load", "freshness", "build", "export"]
RUN_LOG = os.path.join(config.RAW_DIR, "run_log.csv")


def dbt(*args):
    return [sys.executable, "-m", "dbt.cli.main", *args]


def run(label, cmd, cwd, dry_run):
    print("\n" + "=" * 70)
    print("%s\n  %s" % (label, " ".join(cmd)))
    print("=" * 70, flush=True)
    if dry_run:
        return 0
    started = time.time()
    code = subprocess.run(cmd, cwd=str(cwd)).returncode
    print("-> %s finished with exit code %d in %.0fs" % (label, code, time.time() - started), flush=True)
    return code


def write_run_log(row):
    os.makedirs(os.path.dirname(RUN_LOG), exist_ok=True)
    # The run log must never crash a finished run. If run_log.csv is locked (open in Excel),
    # the row goes to run_log_pending.csv next to it; copy it across once Excel is closed.
    for path in (RUN_LOG, RUN_LOG.replace(".csv", "_pending.csv")):
        try:
            new_file = not os.path.exists(path)
            with open(path, "a", encoding="utf-8-sig", newline="") as f:
                w = csv.DictWriter(f, fieldnames=list(row))
                if new_file:
                    w.writeheader()
                w.writerow(row)
            if path != RUN_LOG:
                print("WARNING: %s is locked (open in Excel?); run logged to %s" % (RUN_LOG, path))
            return
        except PermissionError:
            continue
    print("WARNING: could not write the run log; row: %s" % row)


def main():
    parser = argparse.ArgumentParser(description="Run the job-market pipeline end to end.")
    parser.add_argument("--steps", nargs="+", choices=ALL_STEPS, default=ALL_STEPS,
                        help="steps to run, always in pipeline order (default: all)")
    parser.add_argument("--sources", nargs="+", choices=sorted(EXTRACTORS), default=ATS_SOURCES,
                        help="sources to extract (default: the four ATS boards)")
    parser.add_argument("--dry-run", action="store_true", help="print the commands, run nothing")
    args = parser.parse_args()

    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    os.environ["PIPELINE_RUN_ID"] = run_id          # inherited by every child process
    started_at = datetime.now(timezone.utc).isoformat()
    steps = [s for s in ALL_STEPS if s in args.steps]
    print("run_id %s | steps: %s | extract: %s%s"
          % (run_id, ", ".join(steps), ", ".join(args.sources), " | DRY RUN" if args.dry_run else ""))

    failed_step = None

    for step in steps:
        if step == "extract":
            for source in args.sources:
                if run("extract " + source, [sys.executable, *EXTRACTORS[source]], SRC_DIR, args.dry_run):
                    failed_step = "extract " + source
                    break
        elif step == "upload":
            if run("upload to ADLS", [sys.executable, "pipeline/landing/upload_to_adls.py"],
                   SRC_DIR, args.dry_run):
                failed_step = "upload"
        elif step == "load":
            if run("COPY INTO RAW", dbt("run-operation", "load_raw"), DBT_DIR, args.dry_run):
                failed_step = "load"
        elif step == "freshness":
            # warn_after only prints (exit code 0). error_after (employer boards older than 15 days,
            # models/sources.yml) exits non-zero and stops the run before build, so the lifecycle is
            # never recomputed and exported from stale board snapshots.
            if run("source freshness", dbt("source", "freshness"), DBT_DIR, args.dry_run):
                failed_step = "freshness"
        elif step == "build":
            if run("dbt build", dbt("build"), DBT_DIR, args.dry_run):
                failed_step = "build"
        elif step == "export":
            # runs only after a green build (a failed build stops the loop first), so ADLS
            # curated/ only ever receives tested marts
            if run("export MARTS to ADLS curated/",
                   dbt("run-operation", "export_marts", "--args", "{run_id: %s}" % run_id),
                   DBT_DIR, args.dry_run):
                failed_step = "export"
        if failed_step:
            break

    status = "failed" if failed_step else ("dry_run" if args.dry_run else "succeeded")
    print("\n" + "=" * 70)
    print("run %s %s%s" % (run_id, status.upper(), " at step: " + failed_step if failed_step else ""))
    if not args.dry_run:
        write_run_log({"run_id": run_id, "started_at": started_at,
                       "finished_at": datetime.now(timezone.utc).isoformat(),
                       "steps": " ".join(steps), "extracted_sources": " ".join(args.sources),
                       "status": status, "failed_step": failed_step or "",
                       "warnings": ""})   # column kept so existing run_log.csv files stay aligned
        print("run log: " + RUN_LOG)
    sys.exit(1 if failed_step else 0)


if __name__ == "__main__":
    main()