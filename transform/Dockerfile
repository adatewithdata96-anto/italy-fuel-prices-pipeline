FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    DBT_PROFILES_DIR=/usr/app

WORKDIR /usr/app

COPY requirements.txt ./
RUN pip install -r requirements.txt

# Pre-install the DuckDB extension used to read from S3, so runs do not download it every time
RUN python -c "import duckdb; duckdb.sql('INSTALL httpfs')"

COPY . .

ENTRYPOINT ["dbt"]
CMD ["build", "--target", "local"]
