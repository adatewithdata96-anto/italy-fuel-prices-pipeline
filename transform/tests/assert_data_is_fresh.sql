-- Fails if the most recent price date is older than `freshness_max_days`:
-- usually it means the daily file did not arrive or the ingestion did not run.
-- Disabled in CI, where the data comes from fixed test files.

{{ config(severity='error') }}

{% if var('check_freshness') %}
select max(price_date) as latest_price_date
from {{ ref('fct_daily_prices') }}
having max(price_date) < current_date - {{ var('freshness_max_days') }}
    or max(price_date) is null
{% else %}
select 1 as skipped where false
{% endif %}
