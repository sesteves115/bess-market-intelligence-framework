import pandas as pd
from sqlalchemy import create_engine

user = "root"
password = "*Kousei0511*"
host = "localhost"
port = 3306
db_name = "bess_project"

engine = create_engine(f"mysql+pymysql://{user}:{password}@{host}:{port}/{db_name}")

print("Reading hourly data from MySQL...")
df = pd.read_sql("""
    SELECT 
        balancing_authority_code_eia,
        datetime_utc,
        demand_imputed_pudl_mwh,
        interchange_adjusted_mwh
    FROM out_eia930__hourly_operations
    WHERE datetime_utc >= '2019-01-01'
    ORDER BY balancing_authority_code_eia, datetime_utc
""", con=engine)

print("Calculating demand and interchange ramp rates...")
df = df.sort_values(['balancing_authority_code_eia', 'datetime_utc'])

df['prev_demand'] = df.groupby('balancing_authority_code_eia')['demand_imputed_pudl_mwh'].shift(1)
df['prev_interchange'] = df.groupby('balancing_authority_code_eia')['interchange_adjusted_mwh'].shift(1)

df['demand_ramp'] = (df['demand_imputed_pudl_mwh'] - df['prev_demand']).abs()
df['interchange_ramp'] = (df['interchange_adjusted_mwh'] - df['prev_interchange']).abs()

print("Aggregating by balancing authority...")
ramp_metrics = df.groupby('balancing_authority_code_eia').agg(
    avg_demand_ramp_mwh=('demand_ramp', 'mean'),
    max_demand_ramp_mwh=('demand_ramp', 'max'),
    std_dev_demand_ramp_mwh=('demand_ramp', 'std'),
    avg_interchange_ramp_mwh=('interchange_ramp', 'mean'),
    max_interchange_ramp_mwh=('interchange_ramp', 'max'),
    std_dev_interchange_ramp_mwh=('interchange_ramp', 'std')
).reset_index()

print("Writing to MySQL...")
ramp_metrics.to_sql('module_a_additional_ramps', con=engine, if_exists='replace', index=False)
print(f"Done: {len(ramp_metrics)} rows written")