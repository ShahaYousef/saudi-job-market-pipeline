# -*- coding: utf-8 -*-
"""JSearch collector. Append-only raw landing, resumable.
Key rotation happens INSIDE the fetch function so the same page is retried,
not skipped. Transient 5xx retried separately."""
import sys, time, json, urllib.parse, urllib.request, urllib.error
from pathlib import Path
from datetime import datetime, timezone

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # repo/
from src.common import config, raw_writer, state, query_log

SOURCE_ID = "jsearch"
API_KEYS  = config.jsearch_api_keys()
BASE      = "https://api.openwebninja.com/jsearch/search"

RAW_DIR   = config.raw_dir_for(SOURCE_ID)
LOG_PATH  = config.LOG_PATH
SEEN_PATH = config.seen_path_for(SOURCE_ID)

SLEEP_SECONDS    = 6
MAX_PAGE         = 20    # design cap, NOT a measured source ceiling
MAX_RETRIES      = 3     # 504 is transient
RETRY_BACKOFF    = 15
STOP_AFTER_EMPTY = 2     # partial pages are NOT an end signal

QUERY = {"query": "jobs in Saudi Arabia", "country": "sa", "language": "en", "num_pages": 1}
QUERY_LABEL = "L0_general_sa"
BATCH_ID_OVERRIDE = ""

_key_idx = 0   # module-level: persists across pages and across queries in a matrix run


def make_batch_id(label):
    if BATCH_ID_OVERRIDE:
        return BATCH_ID_OVERRIDE
    return SOURCE_ID + "__" + label + "__" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _raw_call(key, params):
    req = urllib.request.Request(BASE + "?" + urllib.parse.urlencode(params),
                                 headers={"x-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, r.read().decode("utf-8")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode("utf-8", errors="replace")
    except Exception as e:
        return 0, json.dumps({"client_error": str(e)})


def fetch_with_retry(_unused_key, params):
    """Returns (status, raw, attempts).
    Quota errors (401/403/429) rotate the key and retry THE SAME request.
    Transient errors (5xx, network) back off and retry the same key.
    Signature keeps a first positional arg for backwards compatibility."""
    global _key_idx
    attempts = 0
    while True:
        attempts += 1
        s, raw = _raw_call(API_KEYS[_key_idx], params)

        if s == 200:
            return s, raw, attempts

        if s in (401, 403, 429):
            if _key_idx + 1 < len(API_KEYS):
                _key_idx += 1
                print("      http=%s, rotating to key %d/%d, retrying SAME request"
                      % (s, _key_idx + 1, len(API_KEYS)))
                time.sleep(2)
                continue
            print("      http=%s, all %d keys exhausted" % (s, len(API_KEYS)))
            return s, raw, attempts

        if 400 <= s < 500:
            return s, raw, attempts

        if attempts < MAX_RETRIES:
            print("      transient http=%s, retry %d/%d in %ds"
                  % (s, attempts, MAX_RETRIES, RETRY_BACKOFF))
            time.sleep(RETRY_BACKOFF)
            continue
        return s, raw, attempts


def land_raw(batch_id, page, params, status, raw_text, attempts, ts):
    envelope = {
        "source_id":   SOURCE_ID,
        "batch_id":    batch_id,
        "ingested_at": ts,
        "request": {"endpoint": "GET " + BASE, "params": params,
                    "query_hash": raw_writer.query_hash(params), "page": page,
                    "attempts": attempts, "key_index": _key_idx},
        "http_status":  status,
        "response_raw": raw_text,
    }
    ingest_date = ts[:10]
    return raw_writer.write_envelope(RAW_DIR, ingest_date, batch_id, page, envelope)


def run():
    batch_id = make_batch_id(QUERY_LABEL)
    seen = state.load_seen(SEEN_PATH)
    print("batch_id : " + batch_id)
    print("seen ids before this batch: %d" % len(seen))
    empty_streak = 0
    hit_cap = False

    for page in range(1, MAX_PAGE + 1):
        if raw_writer.find_existing_page(RAW_DIR, batch_id, page):
            print("page %3d  skipped, already landed" % page)
            continue

        params = dict(QUERY); params["page"] = page
        status, raw_text, attempts = fetch_with_retry(None, params)
        ts = raw_writer.utc_now()
        land_raw(batch_id, page, params, status, raw_text, attempts, ts)

        rows, new_ids = 0, 0
        if status == 200:
            try:
                d = json.loads(raw_text).get("data") or []
                rows = len(d)
                for j in d:
                    uid = j.get("job_uid")
                    if uid and uid not in seen:
                        seen.add(uid); new_ids += 1
            except json.JSONDecodeError:
                print("page %3d  WARNING: not valid JSON" % page)

        # truncated means we stopped while data was still flowing
        if page == MAX_PAGE and status == 200 and rows > 0:
            hit_cap = True

        query_log.log_row(LOG_PATH, {"batch_id": batch_id, "source_id": SOURCE_ID,
                 "query_label": QUERY_LABEL, "query_hash": raw_writer.query_hash(QUERY),
                 "keywords": QUERY.get("query"), "location": QUERY.get("country"),
                 "page": page, "http_status": status,
                 "total_count_reported": None, "rows_returned": rows,
                 "new_unique_ids": new_ids, "cumulative_unique": len(seen),
                 "truncated_flag": int(hit_cap or status != 200),
                 "executed_at": ts})
        state.save_seen(SEEN_PATH, seen)

        print("page %3d  http=%s  rows=%2d  new=%2d  cum=%d  attempts=%d"
              % (page, status, rows, new_ids, len(seen), attempts))

        if status == 200 and rows == 0:
            empty_streak += 1
            if empty_streak >= STOP_AFTER_EMPTY:
                print("%d consecutive empty pages, stopping" % STOP_AFTER_EMPTY)
                break
        elif status == 200:
            empty_streak = 0
        elif status in (401, 403, 429):
            print("quota exhausted on all keys, stopping")
            break
        elif 400 <= status < 500:
            print("client error %s, stopping" % status)
            break

        time.sleep(SLEEP_SECONDS)

    if hit_cap:
        print("NOTE: hit MAX_PAGE=%d with data still flowing. Window NOT exhausted." % MAX_PAGE)
    print("")
    print("done. raw landed under: " + RAW_DIR)


if __name__ == "__main__":
    run()
