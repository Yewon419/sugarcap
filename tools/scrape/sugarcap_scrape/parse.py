"""Small pure parsing helpers shared by brand scrapers."""

from __future__ import annotations

import re

_NUMBER = re.compile(r"-?\d+(?:[.,]\d+)?")


class ParseError(ValueError):
    """Raised when a nutrition value cannot be read from published text."""


def first_number(text: str, *, field: str, context: str) -> float:
    """Return the first number in `text`. Raises `ParseError` naming the field and context."""
    match = _NUMBER.search(text)
    if match is None:
        raise ParseError(f"{field}: no number in {text!r} ({context})")
    return float(match.group(0).replace(",", ""))


def optional_number(text: str | None) -> float | None:
    """Return the first number in `text`, or None when text is empty or has no number."""
    if text is None:
        return None
    match = _NUMBER.search(text)
    if match is None:
        return None
    return float(match.group(0).replace(",", ""))


def clean_text(text: str) -> str:
    """Collapse whitespace and strip."""
    return re.sub(r"\s+", " ", text).strip()
