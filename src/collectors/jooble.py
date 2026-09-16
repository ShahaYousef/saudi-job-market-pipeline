# -*- coding: utf-8 -*-
import sys, time, json
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # repo/
from src.common import config, raw_writer, state, query_log

import urllib.request, urllib.error

SOURCE_ID  = "jooble"
API_KEYS   = config.jooble_api_keys()

RAW_DIR    = config.raw_dir_for(SOURCE_ID)
LOG_PATH   = config.LOG_PATH
SEEN_PATH  = config.seen_path_for(SOURCE_ID)

SLEEP_SECONDS = 10
MAX_PAGE      = 50
PAGE_SIZE     = 20
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")

QUERY = {"keywords": "", "location": "Saudi Arabia"}
QUERY_LABEL = "L0_general_sa"
BATCH_ID_OVERRIDE = ""   # set to an existing batch_id to resume it


def make_batch_id(label):
    if BATCH_ID_OVERRIDE:
        return BATCH_ID_OVERRIDE
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return SOURCE_ID + "__" + label + "__" + stamp


def fetch_page(key, body):
    url = "https://sa.jooble.org/api/" + key
    data = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        url, data=data, method="POST",
        headers={"Content-Type": "application/json; charset=utf-8",
                 "User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")


def land_raw(batch_id, page, body, status, raw_text, ts):
    envelope = {
        "source_id":   SOURCE_ID,
        "batch_id":    batch_id,
        "ingested_at": ts,
        "request": {
            "endpoint":   "POST https://sa.jooble.org/api/{key}",
            "body":       body,
            "query_hash": raw_writer.query_hash(body),
            "page":       page,
        },
        "http_status":  status,
        "response_raw": raw_text,
    }
    ingest_date = ts[:10]
    return raw_writer.write_envelope(RAW_DIR, ingest_date, batch_id, page, envelope)


def run():
    batch_id = make_batch_id(QUERY_LABEL)
    seen = state.load_seen(SEEN_PATH)
    key = API_KEYS[0]
    print("batch_id : " + batch_id)
    print("seen ids before this batch: %d" % len(seen))

    for page in range(1, MAX_PAGE + 1):
        if raw_writer.find_existing_page(RAW_DIR, batch_id, page):
            print("page %3d  skipped, already landed" % page)
            continue

        body = dict(QUERY)
        body["page"] = page
        status, raw_text = fetch_page(key, body)
        ts = raw_writer.utc_now()
        land_raw(batch_id, page, body, status, raw_text, ts)

        total_count, rows, new_ids = None, 0, 0
        if status == 200:
            try:
                obj = json.loads(raw_text)
                total_count = obj.get("totalCount")
                jobs = obj.get("jobs") or []
                rows = len(jobs)
                for j in jobs:
                    jid = str(j.get("id"))
                    if jid not in seen:
                        seen.add(jid)
                        new_ids += 1
            except json.JSONDecodeError:
                print("page %3d  WARNING: response is not valid JSON" % page)

        truncated = (page == MAX_PAGE and rows == PAGE_SIZE)
        query_log.log_row(LOG_PATH, {
            "batch_id": batch_id, "source_id": SOURCE_ID,
            "query_label": QUERY_LABEL, "query_hash": raw_writer.query_hash(QUERY),
            "keywords": QUERY["keywords"], "location": QUERY["location"],
            "page": page, "http_status": status,
            "total_count_reported": total_count, "rows_returned": rows,
            "new_unique_ids": new_ids, "cumulative_unique": len(seen),
            "truncated_flag": int(truncated), "executed_at": ts,
        })
        state.save_seen(SEEN_PATH, seen)
        print("page %3d  http=%s  rows=%2d  new=%2d  cum_unique=%d  total=%s"
              % (page, status, rows, new_ids, len(seen), total_count))

        if status == 200 and rows == 0:
            print("empty page reached, stopping early")
            break
        if status != 200:
            print("non-200 received, stopping. Inspect the landed file.")
            break
        time.sleep(SLEEP_SECONDS)

    print("")
    print("done. raw landed under: " + RAW_DIR)


if __name__ == "__main__":
    run()
