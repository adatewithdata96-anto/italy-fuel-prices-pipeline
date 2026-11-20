-- One row per station per daily snapshot of the registry.

with source as (
    select * from {{ read_raw_csv('stations', 'anagrafica_impianti_attivi.csv') }}
)

select
    try_cast(idImpianto as bigint)                                   as station_id,
    trim(Gestore)                                                    as operator_name,
    trim(Bandiera)                                                   as brand,
    trim("Tipo Impianto")                                            as station_type,
    trim("Nome Impianto")                                            as station_name,
    trim(Indirizzo)                                                  as address,
    upper(trim(Comune))                                              as municipality,
    upper(trim(Provincia))                                           as province,
    try_cast(replace(trim(Latitudine), ',', '.') as double)          as latitude,
    try_cast(replace(trim(Longitudine), ',', '.') as double)         as longitude,
    cast(dt as date)                                                 as snapshot_date
from source
