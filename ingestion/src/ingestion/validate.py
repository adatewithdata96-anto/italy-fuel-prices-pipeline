"""Light format checks on the raw files.

The raw file is stored unchanged: parsing happens later, in dbt.
Here we only check that the file looks like what we expect, so that a format change at the
source stops the pipeline with a clear error instead of producing wrong numbers downstream.
"""

import re
from dataclasses import dataclass
from datetime import date

DELIMITER = "|"  # MIMIT switched from ";" to "|" on 10 February 2026

# Columns we rely on downstream, compared case-insensitively.
# TODO: confirm against the official metadata PDF.
REQUIRED_COLUMNS: dict[str, set[str]] = {
    "prices": {"idimpianto", "desccarburante", "prezzo", "isself", "dtcomu"},
    "stations": {"idimpianto", "comune", "provincia", "latitudine", "longitudine"},
}

_EXTRACTION_RE = re.compile(r"Estrazione del\s+(\d{4}-\d{2}-\d{2})", re.IGNORECASE)


class SourceFormatError(ValueError):
    """The source file does not have the expected format."""


@dataclass(frozen=True)
class ValidationResult:
    extraction_date: date | None
    columns: list[str]
    data_rows: int
    has_extraction_line: bool


def decode(content: bytes) -> str:
    """Decode the file, falling back to latin-1 if it is not valid UTF-8."""
    for encoding in ("utf-8-sig", "latin-1"):
        try:
            return content.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise SourceFormatError("Unable to decode file")  # pragma: no cover (latin-1 never fails)


def parse_extraction_date(line: str) -> date | None:
    """Return the date in a line like 'Estrazione del 2026-11-18', or None."""
    match = _EXTRACTION_RE.search(line)
    if not match:
        return None
    return date.fromisoformat(match.group(1))


def validate(content: bytes, dataset: str) -> ValidationResult:
    if dataset not in REQUIRED_COLUMNS:
        raise ValueError(f"Unknown dataset: {dataset}")
    if not content.strip():
        raise SourceFormatError(f"{dataset}: the file is empty")

    lines = [line for line in decode(content).splitlines() if line.strip()]

    extraction_date = parse_extraction_date(lines[0])
    has_extraction_line = extraction_date is not None
    header_index = 1 if has_extraction_line else 0

    if len(lines) <= header_index:
        raise SourceFormatError(f"{dataset}: header row not found")

    header = lines[header_index]
    if DELIMITER not in header:
        raise SourceFormatError(
            f"{dataset}: expected '{DELIMITER}' as separator, got header: {header[:120]!r}"
        )

    columns = [column.strip() for column in header.split(DELIMITER)]
    missing = REQUIRED_COLUMNS[dataset] - {column.lower() for column in columns}
    if missing:
        raise SourceFormatError(f"{dataset}: missing columns {sorted(missing)}; found {columns}")

    data_rows = len(lines) - header_index - 1
    if data_rows == 0:
        raise SourceFormatError(f"{dataset}: the file has a header but no data rows")

    return ValidationResult(
        extraction_date=extraction_date,
        columns=columns,
        data_rows=data_rows,
        has_extraction_line=has_extraction_line,
    )
