# -*- coding: utf-8 -*-
"""Paths and API keys, shared by every script. Loads .env from 02_code/.

Layout of the submission package (paths resolved from this file, never from the working directory):

    <repo>/02_code/02_src/pipeline/common/config.py   this file
    <repo>/02_code/.env                              API keys, ADLS SAS, Snowflake login
    <repo>/../raw/                                   local landing zone, outside the repo

The landing zone stays next to the repository, as before the repository was reorganised, so raw
files already collected are found without moving them. Set JOB_PIPELINE_RAW_DIR to use another
folder.
"""
import os
from pathlib import Path

try:
    from dotenv import load_dotenv
except ImportError:
    load_dotenv = None

_THIS_DIR    = Path(__file__).resolve().parent        # 02_code/02_src/pipeline/common
PIPELINE_DIR = _THIS_DIR.parent                       # 02_code/02_src/pipeline
SRC_DIR      = PIPELINE_DIR.parent                    # 02_code/02_src
CODE_DIR     = SRC_DIR.parent                         # 02_code
REPO_DIR     = CODE_DIR.parent                        # repository root
CAP_DIR      = str(REPO_DIR.parent)                   # folder that holds the repository and raw/

if load_dotenv is not None:
    load_dotenv(CODE_DIR / ".env")

RAW_DIR  = os.environ.get("JOB_PIPELINE_RAW_DIR") or os.path.join(CAP_DIR, "raw")
LOG_PATH = os.path.join(RAW_DIR, "query_log.csv")


def _keys_from_env(var_name):
    raw = os.environ.get(var_name, "").strip()
    if not raw:
        raise RuntimeError(
            "%s is not set. Copy 02_code/.env.example to 02_code/.env and fill in real keys."
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
