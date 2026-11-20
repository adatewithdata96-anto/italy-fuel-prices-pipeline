{#
    Reads every daily partition of a raw MIMIT file as text.
    `dt` (the reference date) comes from the folder name: prices/dt=YYYY-MM-DD/...
    The file is pipe-separated since 10 February 2026 and starts with an "Estrazione del ..." line.
#}
{% macro read_raw_csv(dataset, filename) -%}
    read_csv(
        '{{ var("raw_path") }}/{{ dataset }}/dt=*/{{ filename }}',
        delim = '|',
        header = true,
        skip = {{ var("csv_skip_rows") }},
        hive_partitioning = true,
        all_varchar = true
    )
{%- endmacro %}
