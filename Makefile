# Works from PowerShell, Command Prompt, Git Bash, macOS and Linux:
# every recipe uses only commands available on all of them (docker, python, ruff, echo).

COMPOSE := docker compose

.DEFAULT_GOAL := help
.PHONY: help up ingest transform pipeline docs test lint dbt-ci down clean

help:
	@echo Available commands:
	@echo   make up         Start storage and dashboard
	@echo   make ingest     Download the latest MIMIT files into the data lake
	@echo   make transform  Run dbt build (models + tests)
	@echo   make pipeline   Ingest, then transform
	@echo   make dbt-ci     Run dbt on the sample files (what CI runs)
	@echo   make docs       Generate and serve the dbt docs on http://localhost:8080
	@echo   make test       Run the Python unit tests
	@echo   make lint       Lint and format-check the Python code
	@echo   make down       Stop all containers
	@echo   make clean      Stop everything and delete the data volumes

up:
	$(COMPOSE) up -d --build rustfs dashboard

ingest:
	$(COMPOSE) --profile jobs run --rm --build ingestion

transform:
	$(COMPOSE) --profile jobs run --rm --build dbt

pipeline: ingest transform

docs:
	$(COMPOSE) --profile jobs run --rm dbt docs generate --target local
	$(COMPOSE) --profile docs up --build dbt-docs

test:
	cd ingestion && python -m pytest

lint:
	cd ingestion && ruff check . && ruff format --check .

dbt-ci:
	$(COMPOSE) --profile jobs run --rm -v "$(CURDIR)/ingestion/tests/fixtures:/fixtures" dbt build --target ci --vars "{raw_path: /fixtures/raw, check_freshness: false}"

down:
	$(COMPOSE) --profile jobs --profile docs down

clean:
	$(COMPOSE) --profile jobs --profile docs down -v
