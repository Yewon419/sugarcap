"""HTTP helpers: retry with logging, then raise with full request context."""

from __future__ import annotations

import logging
import time
from collections.abc import Mapping

import httpx

log = logging.getLogger(__name__)

USER_AGENT = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0 Safari/537.36"
)
MAX_ATTEMPTS = 3
BACKOFF_SECONDS = 1.5


class FetchError(RuntimeError):
    """Raised after every retry failed. Message carries method, URL, params, status, body."""


def make_client() -> httpx.Client:
    return httpx.Client(
        headers={"User-Agent": USER_AGENT, "Accept-Language": "ko-KR,ko;q=0.9"},
        timeout=httpx.Timeout(30.0),
        follow_redirects=True,
    )


def fetch_text(
    client: httpx.Client,
    url: str,
    *,
    method: str = "GET",
    params: Mapping[str, str] | None = None,
    data: Mapping[str, str] | None = None,
    encoding: str | None = None,
) -> str:
    """Fetch a URL as text. Retries transient failures, then raises `FetchError`."""
    last_detail = ""
    for attempt in range(1, MAX_ATTEMPTS + 1):
        try:
            response = client.request(method, url, params=params, data=data)
        except httpx.HTTPError as exc:
            last_detail = f"transport error: {exc!r}"
            log.warning("attempt %d/%d %s %s failed: %s", attempt, MAX_ATTEMPTS, method, url, exc)
        else:
            if response.status_code == 200:
                if encoding is not None:
                    response.encoding = encoding
                return response.text
            last_detail = f"status {response.status_code}, body[:500]={response.text[:500]!r}"
            log.warning(
                "attempt %d/%d %s %s returned %d",
                attempt,
                MAX_ATTEMPTS,
                method,
                url,
                response.status_code,
            )
        if attempt < MAX_ATTEMPTS:
            time.sleep(BACKOFF_SECONDS * attempt)
    raise FetchError(
        f"{method} {url} params={dict(params or {})} data={dict(data or {})} failed after "
        f"{MAX_ATTEMPTS} attempts: {last_detail}"
    )
