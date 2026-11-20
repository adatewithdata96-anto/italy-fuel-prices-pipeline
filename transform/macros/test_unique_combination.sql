{#
    Generic model-level test: the given columns together must be unique.
    Example: unique_combination(combination="price_date, province")
#}
{% test unique_combination(model, combination) %}
select {{ combination }}, count(*) as n
from {{ model }}
group by {{ combination }}
having count(*) > 1
{% endtest %}
