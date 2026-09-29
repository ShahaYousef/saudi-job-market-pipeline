# -*- coding: utf-8 -*-
"""Envelope timestamp/hash helpers and the Hive-style partitioned raw output path.

Layout: raw/<source>/ingest_date=YYYY-MM-DD/<batch_id>__page_NNN.json
The batch_id moves into the filename because pages from different batches now
share a partition directory and would otherwise collide.
"""
import glob
import hashlib
import json
import os
from datetime import datetime, timezone


def utc_now():
    return datetime.now(timezone.utc).isoformat()


def query_hash(obj):
    canon = json.dumps(obj, sort_keys=True, ensure_ascii=False)
    return hashlib.sha256(canon.encode("utf-8")).hexdigest()[:16]


def page_filename(batch_id, page):
    return "%s__page_%03d.json" % (batch_id, page)


def partition_dir(raw_dir, ingest_date):
    return os.path.join(raw_dir, "ingest_date=" + ingest_date)


def find_existing_page(raw_dir, batch_id, page):
    """Resume check. Searches every ingest_date partition, not just today's,
    so a batch that started before a UTC midnight boundary still resumes
    correctly. A landed page counts as complete only if its http_status is
    200; a landed failure (any other status, or a file that can't be parsed)
    is treated as not-yet-landed so the page is re-requested and the file
    overwritten. Returns the path of a completed page if found, else None."""
    pattern = os.path.join(raw_dir, "ingest_date=*", page_filename(batch_id, page))
    for path in glob.glob(pattern):
        try:
            with open(path, "r", encoding="utf-8") as f:
                envelope = json.load(f)
        except (OSError, ValueError):
            continue
        if envelope.get("http_status") == 200:
            return path
    return None


def write_envelope(raw_dir, ingest_date, batch_id, page, envelope):
    out_dir = partition_dir(raw_dir, ingest_date)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, page_filename(batch_id, page))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(envelope, f, ensure_ascii=False, indent=1)
    return path
