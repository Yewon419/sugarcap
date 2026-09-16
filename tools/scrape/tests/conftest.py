from __future__ import annotations

from collections.abc import Iterator

import httpx
import pytest

from sugarcap_scrape.http import make_client


@pytest.fixture(scope="session")
def client() -> Iterator[httpx.Client]:
    with make_client() as c:
        yield c
