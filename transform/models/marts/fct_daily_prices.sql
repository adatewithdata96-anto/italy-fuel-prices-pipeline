-- Core fact table. Grain: station × fuel label × service mode × day.

select
    md5(concat_ws('|', cast(station_id as varchar), fuel_label,
               cast(is_self_service as varchar), cast(price_date as varchar))) as price_key,
    price_date,
    station_id,
    fuel_label,
    fuel_category,
    is_premium,
    is_self_service,
    unit,
    price_eur,
    communicated_at,
    -- Days between the last price communication and the reference date: stale prices are suspicious.
    date_diff('day', cast(communicated_at as date), price_date) as days_since_communication
from {{ ref('int_prices__normalized') }}
