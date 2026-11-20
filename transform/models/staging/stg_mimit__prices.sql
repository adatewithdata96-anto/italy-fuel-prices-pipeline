-- One row per raw price record, with clean names and types.
-- Column names follow the MIMIT metadata (TODO: confirm with the official PDF).

with source as (
    select * from {{ read_raw_csv('prices', 'prezzo_alle_8.csv') }}
)

select
    try_cast(idImpianto as bigint)                                   as station_id,
    trim(descCarburante)                                             as fuel_label,
    try_cast(replace(trim(prezzo), ',', '.') as decimal(8, 3))       as price_eur,
    trim(isSelf) = '1'                                               as is_self_service,
    try_strptime(trim(dtComu), '%d/%m/%Y %H:%M:%S')                  as communicated_at,
    cast(dt as date)                                                 as price_date
from source
