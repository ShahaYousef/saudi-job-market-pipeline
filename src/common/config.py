# -*- coding: utf-8 -*-
"""Paths and API keys, shared by both collectors. Loads .env from the repo root."""
import os
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

_THIS_DIR = Path(__file__).resolve().parent          # repo/src/common
SRC_DIR   = _THIS_DIR.parent                          # repo/src
REPO_DIR  = SRC_DIR.parent                            # repo
CAP_DIR   = str(REPO_DIR.parent)                      # capstone (sibling of repo/, holds raw/)

if load_dotenv is not None:
    load_dotenv(REPO_DIR / ".env")

RAW_DIR  = os.path.join(CAP_DIR, "raw")
LOG_PATH = os.path.join(RAW_DIR, "query_log.csv")


def _keys_from_env(var_name):
    raw = os.environ.get(var_name, "").strip()
    if not raw:
        raise RuntimeError(
            "%s is not set. Copy .env.example to .env in the repo root and fill in real keys."
            % var_name
        )
    keys = [k.strip() for k in raw.split(",") if k.strip()]
    if not keys:
        raise RuntimeError("%s is set but contains no keys." % var_name)
    return keys


def jooble_api_keys():
    return _keys_from_env("JOOBLE_API_KEYS")


def jsearch_api_keys():
    return _keys_from_env("JSEARCH_API_KEYS")


def raw_dir_for(source_id):
    return os.path.join(RAW_DIR, source_id)


def seen_path_for(source_id):
    return os.path.join(RAW_DIR, source_id + "_seen_ids.json")
