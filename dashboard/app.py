"""Streamlit dashboard: where is fuel cheapest today?

Reads the dbt marts from the DuckDB file in read-only mode.
"""

import os

import duckdb
import pandas as pd
import streamlit as st

DUCKDB_PATH = os.getenv("DUCKDB_PATH", "/data/fuel.duckdb")

FUEL_LABELS = {
    "petrol": "Petrol (Benzina)",
    "diesel": "Diesel (Gasolio)",
    "lpg": "LPG (GPL)",
    "methane": "Methane (Metano)",
}

st.set_page_config(page_title="Italy Fuel Prices", page_icon="⛽", layout="wide")


@st.cache_data(ttl=300)
def query(sql: str, params: tuple = ()) -> pd.DataFrame:
    # Open and close a read-only connection for each query, so dbt can write in between.
    with duckdb.connect(DUCKDB_PATH, read_only=True) as con:
        return con.execute(sql, list(params)).df()


def data_available() -> bool:
    if not os.path.exists(DUCKDB_PATH):
        return False
    try:
        query("select 1 from marts.mart_province_daily_avg limit 1")
        return True
    except duckdb.Error:
        return False


st.title("⛽ Where is fuel cheapest in Italy?")
st.caption("Source: MIMIT open data (IODL 2.0) · Prices in force at 8:00 AM on the reference date")

if not data_available():
    st.info("No data yet. Run `make pipeline` to download today's prices and build the models.")
    st.stop()

# --- Filters -----------------------------------------------------------------------------------
dates = query("select distinct price_date from marts.mart_province_daily_avg order by 1 desc")
provinces = query("select distinct province from marts.mart_province_daily_avg order by 1")

with st.sidebar:
    st.header("Filters")
    price_date = st.selectbox("Reference date", dates["price_date"], format_func=str)
    default_province = (
        provinces["province"].tolist().index("BA") if "BA" in provinces["province"].tolist() else 0
    )
    province = st.selectbox("Province", provinces["province"], index=default_province)
    fuel = st.selectbox("Fuel", list(FUEL_LABELS), format_func=FUEL_LABELS.get)
    self_service = st.toggle("Self-service", value=True)

params = (price_date, province, fuel, self_service)
filters = """
    price_date = ? and province = ? and fuel_category = ? and is_self_service = ?
"""

# --- KPIs --------------------------------------------------------------------------------------
today = query(f"select * from marts.mart_province_daily_avg where {filters}", params)
previous = query(
    """
    select avg_price_eur from marts.mart_province_daily_avg
    where price_date < ? and province = ? and fuel_category = ? and is_self_service = ?
    order by price_date desc limit 1
    """,
    params,
)
cheapest = query(
    f"select * from marts.mart_cheapest_stations where {filters} order by price_rank, price_eur",
    params,
)

if today.empty:
    st.warning("No prices for this combination. Try another fuel, province or service mode.")
    st.stop()

row = today.iloc[0]
unit = row["unit"]
delta = None
if not previous.empty:
    delta = f"{row['avg_price_eur'] - previous.iloc[0]['avg_price_eur']:+.3f} €"

col1, col2, col3, col4 = st.columns(4)
col1.metric(
    f"Average price (€/{unit})", f"{row['avg_price_eur']:.3f}", delta, delta_color="inverse"
)
col2.metric("Cheapest", f"{row['min_price_eur']:.3f}")
col3.metric("Most expensive", f"{row['max_price_eur']:.3f}")
col4.metric("Stations", int(row["station_count"]))

# --- Cheapest stations -------------------------------------------------------------------------
left, right = st.columns([3, 2])

with left:
    st.subheader("Top 10 cheapest stations")
    st.dataframe(
        cheapest[
            [
                "price_rank",
                "station_name",
                "brand",
                "municipality",
                "address",
                "price_eur",
                "diff_from_avg_eur",
            ]
        ].rename(
            columns={
                "price_rank": "#",
                "station_name": "Station",
                "brand": "Brand",
                "municipality": "Municipality",
                "address": "Address",
                "price_eur": f"€/{unit}",
                "diff_from_avg_eur": "vs average",
            }
        ),
        hide_index=True,
        use_container_width=True,
    )

with right:
    st.subheader("Map")
    points = cheapest.dropna(subset=["latitude", "longitude"])
    if points.empty:
        st.caption("No coordinates available.")
    else:
        st.map(points, latitude="latitude", longitude="longitude", size=60)

# --- Trend -------------------------------------------------------------------------------------
st.subheader(f"Average price over time · {province}")
trend = query(
    """
    select price_date, avg_price_eur, min_price_eur
    from marts.mart_province_daily_avg
    where province = ? and fuel_category = ? and is_self_service = ?
    order by price_date
    """,
    (province, fuel, self_service),
)
if len(trend) < 2:
    st.caption("The trend appears after at least two days of data.")
else:
    st.line_chart(trend.set_index("price_date"))
