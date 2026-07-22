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
        net_generation_imputed_eia_mwh
    FROM out_eia930__hourly_operations
    WHERE datetime_utc >= '2019-01-01'
    ORDER BY balancing_authority_code_eia, datetime_utc
""", con=engine)

print("Calculating ramp rates...")
df = df.sort_values(['balancing_authority_code_eia', 'datetime_utc'])
df['prev_hour_gen'] = df.groupby('balancing_authority_code_eia')['net_generation_imputed_eia_mwh'].shift(1)
df['hourly_ramp'] = (df['net_generation_imputed_eia_mwh'] - df['prev_hour_gen']).abs()

print("Aggregating by balancing authority...")
ramp_metrics = df.groupby('balancing_authority_code_eia').agg(
    avg_ramp_rate_mwh=('hourly_ramp', 'mean'),
    max_ramp_rate_mwh=('hourly_ramp', 'max'),
    std_dev_ramp_rate_mwh=('hourly_ramp', 'std')
).reset_index()

print("Writing to MySQL...")
ramp_metrics.to_sql('module_a_ramp_rates', con=engine, if_exists='replace', index=False)
print(f"Done: {len(ramp_metrics)} rows written")