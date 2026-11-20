FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY pyproject.toml ./
COPY src ./src
RUN pip install .

# Run as a non-root user
RUN useradd --create-home --uid 1000 app
USER app

ENTRYPOINT ["python", "-m", "ingestion.main"]
