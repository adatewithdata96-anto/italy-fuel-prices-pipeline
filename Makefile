.DEFAULT_GOAL := help
COMPOSE := docker compose

.PHONY: help up ingest transform pipeline docs test lint dbt-ci down clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'

up: ## Start storage and dashboard
	$(COMPOSE) up -d --build rustfs dashboard

ingest: ## Download today's MIMIT files into the data lake
	$(COMPOSE) --profile jobs run --rm --build ingestion

transform: ## Run dbt build (models + tests)
	$(COMPOSE) --profile jobs run --rm --build dbt

pipeline: ingest transform ## Ingest, then transform

docs: ## Generate and serve the dbt docs on http://localhost:8080
	$(COMPOSE) --profile jobs run --rm dbt docs generate --target local
	$(COMPOSE) --profile docs up --build dbt-docs

test: ## Run the Python unit tests
	cd ingestion && python -m pytest

lint: ## Lint and format-check the Python code
	cd ingestion && ruff check . && ruff format --check .

dbt-ci: ## Build dbt on the test fixtures (what CI runs)
	$(COMPOSE) --profile jobs run --rm -v $(CURDIR)/ingestion/tests/fixtures:/fixtures dbt \
		build --target ci --vars '{raw_path: "/fixtures/raw", check_freshness: false}'

down: ## Stop all containers
	$(COMPOSE) --profile jobs --profile docs down

clean: ## Stop everything and delete the data volumes
	$(COMPOSE) --profile jobs --profile docs down -v
