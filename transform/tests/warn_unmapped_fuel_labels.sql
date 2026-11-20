-- Warns when more than 5% of the latest day's prices have an unmapped fuel label ('other').
-- Fix: add the new labels to seeds/fuel_label_overrides.csv.

{{ config(severity='warn') }}

with latest as (
    select *
    from {{ ref('fct_daily_prices') }}
    where price_date = (select max(price_date) from {{ ref('fct_daily_prices') }})
)

select
    count(*) filter (where fuel_category = 'other') as unmapped_rows,
    count(*) as total_rows,
    list(distinct fuel_label) filter (where fuel_category = 'other') as unmapped_labels
from latest
having count(*) filter (where fuel_category = 'other') > 0.05 * count(*)
