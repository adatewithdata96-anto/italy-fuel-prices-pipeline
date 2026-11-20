-- One row per station, from the most recent registry snapshot that contains it.

select
    station_id,
    station_name,
    operator_name,
    brand,
    station_type,
    address,
    municipality,
    province,
    latitude,
    longitude,
    snapshot_date as last_seen_date
from {{ ref('stg_mimit__stations') }}
where station_id is not null
qualify row_number() over (partition by station_id order by snapshot_date desc) = 1
