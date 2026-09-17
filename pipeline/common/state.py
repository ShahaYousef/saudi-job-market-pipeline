# -*- coding: utf-8 -*-
"""seen_ids load/save, identical logic in both collectors, parameterised by path."""
import json
import os


def load_seen(seen_path):
    if os.path.exists(seen_path):
        with open(seen_path, "r", encoding="utf-8") as f:
            return set(json.load(f))
    return set()


def save_seen(seen_path, seen):
    os.makedirs(os.path.dirname(seen_path), exist_ok=True)
    with open(seen_path, "w", encoding="utf-8") as f:
        json.dump(sorted(seen), f)
