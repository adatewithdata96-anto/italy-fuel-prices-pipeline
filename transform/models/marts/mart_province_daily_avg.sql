-- Daily price statistics per province, fuel category and service mode.
-- Only standard fuels (no brand premium products), like MIMIT's official averages.

select
    prices.price_date,
    stations.province,
    prices.fuel_category,
    prices.unit,
    prices.is_self_service,
    round(avg(prices.price_eur), 3)       as avg_price_eur,
    min(prices.price_eur)                 as min_price_eur,
    max(prices.price_eur)                 as max_price_eur,
    count(distinct prices.station_id)     as station_count
from {{ ref('fct_daily_prices') }} as prices
inner join {{ ref('dim_stations') }} as stations
    on prices.station_id = stations.station_id
where not prices.is_premium
group by all
