from datetime import date
from pathlib import Path

import pytest

from ingestion.validate import SourceFormatError, parse_extraction_date, validate

FIXTURES = Path(__file__).parent / "fixtures" / "raw"


def test_parse_extraction_date():
    assert parse_extraction_date("Estrazione del 2026-11-18") == date(2026, 11, 18)
    assert parse_extraction_date("idImpianto|descCarburante") is None


def test_validate_prices_fixture():
    content = (FIXTURES / "prices" / "dt=2026-11-18" / "prezzo_alle_8.csv").read_bytes()
    result = validate(content, "prices")
    assert result.extraction_date == date(2026, 11, 18)
    assert result.has_extraction_line
    assert result.data_rows == 13
    assert "descCarburante" in result.columns


def test_validate_stations_fixture():
    content = (
        FIXTURES / "stations" / "dt=2026-11-18" / "anagrafica_impianti_attivi.csv"
    ).read_bytes()
    result = validate(content, "stations")
    assert result.data_rows == 4
    assert "Tipo Impianto" in result.columns


def test_file_without_extraction_line_is_accepted():
    content = (
        b"idImpianto|descCarburante|prezzo|isSelf|dtComu\n1|Benzina|1.8|1|01/01/2026 08:00:00\n"
    )
    result = validate(content, "prices")
    assert result.extraction_date is None
    assert result.data_rows == 1


def test_old_semicolon_format_is_rejected():
    content = (
        b"Estrazione del 2026-01-01\n"
        b"idImpianto;descCarburante;prezzo;isSelf;dtComu\n"
        b"1;Benzina;1.8;1;01/01/2026 08:00:00\n"
    )
    with pytest.raises(SourceFormatError, match="separator"):
        validate(content, "prices")


def test_missing_column_is_rejected():
    content = b"idImpianto|descCarburante|prezzo|dtComu\n1|Benzina|1.8|01/01/2026 08:00:00\n"
    with pytest.raises(SourceFormatError, match="isself"):
        validate(content, "prices")


def test_empty_file_is_rejected():
    with pytest.raises(SourceFormatError, match="empty"):
        validate(b"   \n", "prices")


def test_header_without_rows_is_rejected():
    with pytest.raises(SourceFormatError, match="no data rows"):
        validate(b"idImpianto|descCarburante|prezzo|isSelf|dtComu\n", "prices")
