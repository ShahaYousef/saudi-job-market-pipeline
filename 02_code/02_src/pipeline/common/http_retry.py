# pipeline/common/http_retry.py
# -*- coding: utf-8 -*-
"""GET with retries for the four ATS extraction scripts.
 
Retries what is worth retrying (timeouts, connection errors, HTTP 429 and 5xx) with exponential
backoff, honouring Retry-After when the server sends it. Returns (404, None) for a board that does
not exist, so the caller can skip it. Anything else that still fails raises FetchError, which the
caller catches per board: one bad board no longer stops the whole run.
"""
import time
 
import requests
 
RETRY_STATUS = {429, 500, 502, 503, 504}
 
 
class FetchError(Exception):
    def __init__(self, url, status, reason):
        super().__init__("%s -> %s" % (url, reason))
        self.url = url
        self.status = status      # last HTTP status, or None for a network error
 
 
def _wait_seconds(response, attempt, backoff):
    retry_after = response.headers.get("Retry-After") if response is not None else None
    if retry_after and retry_after.isdigit():
        return min(int(retry_after), 120)
    return backoff * (2 ** (attempt - 1))          # 5, 10, 20 ... seconds
 
 
def get_json(url, params=None, timeout=30, max_attempts=4, backoff=5):
    """Returns (status, parsed JSON). (404, None) when the resource does not exist."""
    for attempt in range(1, max_attempts + 1):
        response = None
        try:
            response = requests.get(url, params=params, timeout=timeout)
        except requests.exceptions.RequestException as e:   # timeouts, resets, broken streams
            if attempt == max_attempts:
                raise FetchError(url, None, type(e).__name__)
        else:
            if response.status_code == 404:
                return 404, None
            if response.status_code == 200:
                try:
                    return 200, response.json()
                except ValueError:
                    raise FetchError(url, 200, "response is not valid JSON")
            if response.status_code not in RETRY_STATUS or attempt == max_attempts:
                raise FetchError(url, response.status_code, "HTTP %s" % response.status_code)
 
        wait = _wait_seconds(response, attempt, backoff)
        print("    retry %d/%d in %ds (%s)" % (attempt, max_attempts - 1, wait,
              "HTTP %s" % response.status_code if response is not None else "network error"))
        time.sleep(wait)
