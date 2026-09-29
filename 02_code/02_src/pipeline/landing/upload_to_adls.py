# -*- coding: utf-8 -*-
"""Upload landed raw files to ADLS Gen2 (Phase 2).

Mirrors the local landing zone into the ADLS container, keeping the same layout:

    local:  <raw>/<source>/ingest_date=YYYY-MM-DD/<file>
    ADLS:   <container>/<source>/ingest_date=YYYY-MM-DD/<file>

<raw> is the folder set in pipeline/common/config.py (raw/ next to the repo), where every
extraction script writes. Only files inside an ingest_date= folder are uploaded, so the
seen-ID files, the query log and probe outputs stay local.

Raw is immutable: a file that already exists in ADLS is never overwritten, only skipped.
The one exception is a 0-byte copy of a non-empty local file, which is what an interrupted
upload leaves behind; it is replaced, and reported. Re-running the script is always safe.

Uses the Blob endpoint of the account (<account>.blob.core.windows.net), the same endpoint
the Snowflake stage reads from. Each file is written in a single request, so an upload
lands the whole file or nothing.

Needs in 02_code/.env (see 02_code/.env.example):
    ADLS_ACCOUNT_NAME   storage account name
    ADLS_CONTAINER      container name, default "raw"
    ADLS_SAS_TOKEN      SAS scoped to the container, with Read, Add, Create, Write and List

Run from 02_code/02_src:
    py pipeline/landing/upload_to_adls.py                    all sources
    py pipeline/landing/upload_to_adls.py --source ashby     one source (repeatable)
    py pipeline/landing/upload_to_adls.py --dry-run          show what would be uploaded
"""
import argparse
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # pipeline/
from common import config

from azure.core.exceptions import AzureError, ResourceExistsError
from azure.storage.blob import BlobServiceClient

SOURCES = ["ashby", "workable", "greenhouse", "smartrecruiters", "jooble", "jsearch"]
PARTITION = re.compile(r"^ingest_date=\d{4}-\d{2}-\d{2}$")


def env(name, default=None):
    value = (os.environ.get(name) or default or "").strip()
    if not value:
        raise RuntimeError("%s is not set. Add it to .env (see .env.example)." % name)
    return value


def local_files(source):
    """(local path, ADLS path) for every file inside <raw>/<source>/ingest_date=*/."""
    base = Path(config.raw_dir_for(source))
    if not base.is_dir():
        return
    for partition in sorted(base.iterdir()):
        if partition.is_dir() and PARTITION.match(partition.name):
            for path in sorted(partition.iterdir()):
                if path.is_file() and path.suffix in (".json", ".csv"):
                    yield path, "%s/%s/%s" % (source, partition.name, path.name)


def remote_size(blob):
    """Size in bytes of the remote copy, or None when it does not exist."""
    if not blob.exists():
        return None
    return blob.get_blob_properties().size


def main():
    parser = argparse.ArgumentParser(description="Upload landed raw files to ADLS Gen2.")
    parser.add_argument("--source", choices=SOURCES, action="append",
                        help="limit to one source; repeat for several")
    parser.add_argument("--dry-run", action="store_true",
                        help="list what would be uploaded without uploading")
    args = parser.parse_args()

    account = env("ADLS_ACCOUNT_NAME")
    container = env("ADLS_CONTAINER", "raw")
    sas = env("ADLS_SAS_TOKEN").lstrip("?")

    service = BlobServiceClient(account_url="https://%s.blob.core.windows.net" % account,
                                credential=sas)
    container_client = service.get_container_client(container)

    print("local raw folder : %s" % config.RAW_DIR)
    print("target           : %s/%s%s" % (account, container, "   (dry run)" if args.dry_run else ""))

    verb = "would upload" if args.dry_run else "uploaded"
    totals = {"new": 0, "repaired": 0, "present": 0, "failed": 0}

    for source in args.source or SOURCES:
        new = repaired = present = failed = 0
        for path, remote in local_files(source):
            blob = container_client.get_blob_client(remote)
            try:
                size = remote_size(blob)
                local_size = path.stat().st_size

                if size is not None and not (size == 0 and local_size > 0):
                    present += 1          # real copy already in ADLS: never touched
                    continue

                if size == 0:
                    # left by an interrupted upload: replace the empty placeholder
                    if not args.dry_run:
                        with open(path, "rb") as f:
                            blob.upload_blob(f, overwrite=True)
                    repaired += 1
                    print("  %s %s (replaced an empty copy left by a failed upload)"
                          % ("would repair" if args.dry_run else "repaired", remote))
                    continue

                if not args.dry_run:
                    with open(path, "rb") as f:
                        blob.upload_blob(f, overwrite=False)
                new += 1
                print("  %s %s" % (verb, remote))

            except ResourceExistsError:
                present += 1
            except AzureError as e:
                failed += 1
                print("  FAILED %s: %s" % (remote, str(e).splitlines()[0]))

        print("%-16s %s %4d   repaired %d   already in ADLS %4d   failed %d"
              % (source, verb, new, repaired, present, failed))
        for key, value in (("new", new), ("repaired", repaired), ("present", present), ("failed", failed)):
            totals[key] += value

    print("\ndone at %s: %d %s, %d repaired, %d already present (never overwritten), %d failed"
          % (datetime.now(timezone.utc).isoformat(), totals["new"], verb,
             totals["repaired"], totals["present"], totals["failed"]))
    if totals["failed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()