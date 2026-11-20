-- One price per station, fuel label, service mode and day: the most recently communicated one.

select *
from {{ ref('stg_mimit__prices') }}
where station_id is not null
qualify row_number() over (
    partition by station_id, fuel_label, is_self_service, price_date
    order by communicated_at desc nulls last
) = 1
