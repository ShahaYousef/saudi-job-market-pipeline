# -*- coding: utf-8 -*-
"""query_log.csv append, identical logic and header in both collectors."""
import csv
import os

HEADER = ["batch_id", "source_id", "query_label", "query_hash", "keywords",
          "location", "page", "http_status", "total_count_reported",
          "rows_returned", "new_unique_ids", "cumulative_unique",
          "truncated_flag", "executed_at"]


def log_row(log_path, row):
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    exists = os.path.exists(log_path)
    with open(log_path, "a", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=HEADER)
        if not exists:
            w.writeheader()
        w.writerow(row)
