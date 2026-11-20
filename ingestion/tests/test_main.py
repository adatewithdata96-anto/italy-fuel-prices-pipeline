import json
from datetime import date
from pathlib import Path

import pytest

from ingestion.config import Settings
from ingestion.main import run
from ingestion.validate import SourceFormatError

FIXTURES = Path(__file__).parent / "fixtures" / "raw"

SETTINGS = Settings(
    s3_bucket="fuel-raw",
    prices_url="https://example.org/prezzo_alle_8.csv",
    stations_url="https://example.org/anagrafica_impianti_attivi.csv",
    create_bucket=True,
)

FILES = {
    SETTINGS.prices_url: FIXTURES / "prices" / "dt=2026-11-19" / "prezzo_alle_8.csv",
    SETTINGS.stations_url: FIXTURES
    / "stations"
    / "dt=2026-11-19"
    / "anagrafica_impianti_attivi.csv",
}


class FakeS3:
    """Minimal in-memory stand-in for the boto3 S3 client."""

    def __init__(self):
        self.buckets: set[str] = set()
        self.objects: dict[tuple[str, str], bytes] = {}

    def list_buckets(self):
        return {"Buckets": [{"Name": name} for name in self.buckets]}

    def create_bucket(self, Bucket):  # noqa: N803 (boto3 naming)
        self.buckets.add(Bucket)

    def put_object(self, Bucket, Key, Body, **kwargs):  # noqa: N803
        self.objects[(Bucket, Key)] = Body


def fetch_fixture(url: str) -> bytes:
    return FILES[url].read_bytes()


def test_run_writes_files_and_manifests_partitioned_by_reference_date():
    s3 = FakeS3()
    prefixes = run(SETTINGS, s3, fetch=fetch_fixture, today=date(2026, 11, 20))

    assert prefixes == ["prices/dt=2026-11-19", "stations/dt=2026-11-19"]
    assert "fuel-raw" in s3.buckets
    assert ("fuel-raw", "prices/dt=2026-11-19/prezzo_alle_8.csv") in s3.objects
    assert ("fuel-raw", "stations/dt=2026-11-19/anagrafica_impianti_attivi.csv") in s3.objects

    manifest = json.loads(s3.objects[("fuel-raw", "prices/dt=2026-11-19/_manifest.json")])
    assert manifest["reference_date"] == "2026-11-19"
    assert manifest["data_rows"] == 12
    assert len(manifest["sha256"]) == 64


def test_run_is_idempotent():
    s3 = FakeS3()
    run(SETTINGS, s3, fetch=fetch_fixture, today=date(2026, 11, 20))
    keys_after_first_run = set(s3.objects)
    run(SETTINGS, s3, fetch=fetch_fixture, today=date(2026, 11, 20))
    assert set(s3.objects) == keys_after_first_run


def test_nothing_is_written_if_one_file_is_invalid():
    s3 = FakeS3()

    def broken_stations(url: str) -> bytes:
        if url == SETTINGS.stations_url:
            return b"not|the|right|header\n1|2|3|4\n"
        return fetch_fixture(url)

    with pytest.raises(SourceFormatError):
        run(SETTINGS, s3, fetch=broken_stations, today=date(2026, 11, 20))
    assert s3.objects == {}


def test_falls_back_to_yesterday_without_extraction_line():
    s3 = FakeS3()

    def without_extraction_line(url: str) -> bytes:
        lines = fetch_fixture(url).splitlines(keepends=True)
        return b"".join(lines[1:])

    prefixes = run(SETTINGS, s3, fetch=without_extraction_line, today=date(2026, 11, 20))
    assert prefixes[0] == "prices/dt=2026-11-19"
