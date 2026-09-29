
# pipeline/common/extract_log.py
# -*- coding: utf-8 -*-
"""extract_log.csv: one row per ATS board per run: what was pulled, when, and what was written.
 
Lives in the landing zone next to query_log.csv (raw/extract_log.csv, outside the repo, not uploaded).
It answers "how many records did the script pull, and when?" and gives each landed file a SHA-256,
so a RAW row count can be checked against what the script wrote.
run_id comes from PIPELINE_RUN_ID (set by pipeline/run_pipeline.py) or is created per script run.
"""
import csv
import hashlib
import os
from datetime import datetime, timezone
 
from common import config
 
LOG_PATH = os.path.join(config.RAW_DIR, "extract_log.csv")
HEADER = ["run_id", "source_id", "board", "ingest_date", "extracted_at", "outcome",
          "http_status", "jobs_returned", "jobs_kept", "file_path", "file_sha256", "error"]
 
RUN_ID = os.environ.get("PIPELINE_RUN_ID") or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
 
 
def _sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()
 
 
def log_board(source_id, board, ingest_date, outcome, http_status=None,
              jobs_returned=None, jobs_kept=None, file_path=None, error=None):
    """outcome: 'saved', 'not_found' (404, board skipped) or 'failed' (no file written)."""
    os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
    new_file = not os.path.exists(LOG_PATH)
    with open(LOG_PATH, "a", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=HEADER)
        if new_file:
            w.writeheader()
        w.writerow({
            "run_id": RUN_ID, "source_id": source_id, "board": board, "ingest_date": ingest_date,
            "extracted_at": datetime.now(timezone.utc).isoformat(), "outcome": outcome,
            "http_status": http_status, "jobs_returned": jobs_returned, "jobs_kept": jobs_kept,
            "file_path": file_path,
            "file_sha256": _sha256(file_path) if file_path and os.path.exists(file_path) else None,
            "error": error,
        })
