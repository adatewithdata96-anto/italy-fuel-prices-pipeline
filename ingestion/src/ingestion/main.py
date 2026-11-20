"""Daily ingestion: download the MIMIT files and store them unchanged in the data lake.

Layout in the bucket (one folder per reference date, Hive style):

    prices/dt=YYYY-MM-DD/prezzo_alle_8.csv
    prices/dt=YYYY-MM-DD/_manifest.json
    stations/dt=YYYY-MM-DD/anagrafica_impianti_attivi.csv
    stations/dt=YYYY-MM-DD/_manifest.json

`dt` is the date the prices refer to (read from the file), not the download date.
Re-running the job for the same file overwrites the same keys: the job is idempotent.
"""

import hashlib
import json
import logging
import sys
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

import requests

from ingestion.config import Settings
from ingestion.validate import ValidationResult, validate

log = logging.getLogger("ingestion")


@dataclass(frozen=True)
class Dataset:
    name: str
    filename: str
    url: str


def datasets_from(settings: Settings) -> list[Dataset]:
    return [
        Dataset("prices", "prezzo_alle_8.csv", settings.prices_url),
        Dataset("stations", "anagrafica_impianti_attivi.csv", settings.stations_url),
    ]


def download(url: str, timeout: int, max_attempts: int) -> bytes:
    """Download a file, retrying with exponential backoff on network and server errors."""
    for attempt in range(1, max_attempts + 1):
        try:
            response = requests.get(url, timeout=timeout)
            response.raise_for_status()
            return response.content
        except requests.RequestException as exc:
            if attempt == max_attempts:
                raise
            wait = 2**attempt
            log.warning(
                "Download failed (attempt %d/%d): %s. Retrying in %ds",
                attempt,
                max_attempts,
                exc,
                wait,
            )
            time.sleep(wait)
    raise RuntimeError("unreachable")  # pragma: no cover


def reference_date(result: ValidationResult, today: date) -> date:
    """The date the data refers to.

    MIMIT publishes every day the prices in force at 8:00 of the previous day.
    We trust the date written in the file; if it is missing we fall back to yesterday.
    """
    if result.extraction_date is not None:
        return result.extraction_date
    fallback = today - timedelta(days=1)
    log.warning("Extraction date not found in file, falling back to %s", fallback)
    return fallback


def ensure_bucket(s3: Any, bucket: str) -> None:
    """Create the bucket if it does not exist (local development only)."""
    existing = {b["Name"] for b in s3.list_buckets().get("Buckets", [])}
    if bucket not in existing:
        s3.create_bucket(Bucket=bucket)
        log.info("Created bucket %s", bucket)


def store(
    s3: Any,
    bucket: str,
    dataset: Dataset,
    content: bytes,
    result: ValidationResult,
    ref_date: date,
) -> str:
    prefix = f"{dataset.name}/dt={ref_date.isoformat()}"
    s3.put_object(Bucket=bucket, Key=f"{prefix}/{dataset.filename}", Body=content)

    manifest = {
        "dataset": dataset.name,
        "source_url": dataset.url,
        "reference_date": ref_date.isoformat(),
        "ingested_at": datetime.now(UTC).isoformat(timespec="seconds"),
        "bytes": len(content),
        "sha256": hashlib.sha256(content).hexdigest(),
        "data_rows": result.data_rows,
        "columns": result.columns,
        "has_extraction_line": result.has_extraction_line,
    }
    s3.put_object(
        Bucket=bucket,
        Key=f"{prefix}/_manifest.json",
        Body=json.dumps(manifest, indent=2).encode(),
        ContentType="application/json",
    )
    log.info(
        "Stored %s: %d rows, %d bytes -> s3://%s/%s",
        dataset.name,
        result.data_rows,
        len(content),
        bucket,
        prefix,
    )
    return prefix


def run(
    settings: Settings,
    s3: Any,
    fetch: Callable[[str], bytes] | None = None,
    today: date | None = None,
) -> list[str]:
    """Run the ingestion. `s3`, `fetch` and `today` are injectable for tests."""
    fetch = fetch or (
        lambda url: download(url, settings.http_timeout_seconds, settings.max_attempts)
    )
    today = today or date.today()

    if settings.create_bucket:
        ensure_bucket(s3, settings.s3_bucket)

    # Download and validate everything first: if one file is broken, nothing is written.
    downloaded = []
    for dataset in datasets_from(settings):
        content = fetch(dataset.url)
        result = validate(content, dataset.name)
        downloaded.append((dataset, content, result))

    return [
        store(s3, settings.s3_bucket, dataset, content, result, reference_date(result, today))
        for dataset, content, result in downloaded
    ]


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stdout,
    )
    settings = Settings.from_env()

    import boto3  # imported here so unit tests do not need AWS libraries

    s3 = boto3.client("s3", endpoint_url=settings.s3_endpoint_url)
    try:
        run(settings, s3)
    except Exception:
        log.exception("Ingestion failed")
        return 1
    log.info("Ingestion completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
