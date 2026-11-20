-- Top 10 cheapest stations per day, province, fuel category and service mode,
-- with the gap from the provincial average. Standard fuels only.

with ranked as (
    select
        prices.price_date,
        stations.province,
        prices.fuel_category,
        prices.unit,
        prices.is_self_service,
        prices.station_id,
        stations.station_name,
        stations.brand,
        stations.address,
        stations.municipality,
        stations.latitude,
        stations.longitude,
        prices.price_eur,
        prices.communicated_at,
        rank() over (
            partition by prices.price_date, stations.province, prices.fuel_category,
                         prices.is_self_service
            order by prices.price_eur
        ) as price_rank
    from {{ ref('fct_daily_prices') }} as prices
    inner join {{ ref('dim_stations') }} as stations
        on prices.station_id = stations.station_id
    where not prices.is_premium
)

select
    ranked.*,
    averages.avg_price_eur,
    round(ranked.price_eur - averages.avg_price_eur, 3) as diff_from_avg_eur
from ranked
inner join {{ ref('mart_province_daily_avg') }} as averages
    on  ranked.price_date      = averages.price_date
    and ranked.province        = averages.province
    and ranked.fuel_category   = averages.fuel_category
    and ranked.is_self_service = averages.is_self_service
where ranked.price_rank <= 10
