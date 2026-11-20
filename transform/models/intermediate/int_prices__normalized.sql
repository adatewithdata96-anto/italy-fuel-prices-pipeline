-- Maps brand-specific fuel labels to standard categories and adds the unit of measure.
-- Rules cover the common cases; the seed `fuel_label_overrides` fixes the exceptions.

with prices as (
    select * from {{ ref('int_prices__deduplicated') }}
),

overrides as (
    select lower(trim(fuel_label)) as fuel_label_key, fuel_category
    from {{ ref('fuel_label_overrides') }}
),

categorized as (
    select
        prices.*,
        coalesce(
            overrides.fuel_category,
            case
                when lower(prices.fuel_label) like '%gnl%'
                  or lower(prices.fuel_label) like '%l-gnc%'   then 'lng'
                when lower(prices.fuel_label) like '%metano%'
                  or lower(prices.fuel_label) like '%gnc%'     then 'methane'
                when lower(prices.fuel_label) like '%gpl%'     then 'lpg'
                when lower(prices.fuel_label) like '%hvo%'     then 'hvo'
                when lower(prices.fuel_label) like '%gasolio%'
                  or lower(prices.fuel_label) like '%diesel%'  then 'diesel'
                when lower(prices.fuel_label) like '%benzina%'
                  or lower(prices.fuel_label) like '%super%'   then 'petrol'
                else 'other'
            end
        ) as fuel_category
    from prices
    left join overrides
        on lower(trim(prices.fuel_label)) = overrides.fuel_label_key
)

select
    *,
    -- Standard fuels have exactly these labels; everything else is a brand's premium product.
    lower(fuel_label) not in ('benzina', 'gasolio', 'gpl', 'metano') as is_premium,
    case when fuel_category in ('methane', 'lng') then 'kg' else 'l' end as unit
from categorized
