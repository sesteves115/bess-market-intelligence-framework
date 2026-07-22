import pandas as pd
import sqlalchemy
from sqlalchemy import create_engine

# --- CONFIG ---
user = "root"
password = "*Kousei0511*"
host = "localhost"
port = 3306
db_name = "bess_project"

# --- CONNECTION ---
engine = create_engine(f"mysql+pymysql://{user}:{password}@{host}:{port}/")
with engine.connect() as conn:
    conn.execute(sqlalchemy.text(f"CREATE DATABASE IF NOT EXISTS {db_name}"))

engine = create_engine(f"mysql+pymysql://{user}:{password}@{host}:{port}/{db_name}")

# --- FILE PATHS ---
folder = r"C:\Users\seuni\OneDrive\Documentos\Job Applications\capstone project\PUDL tables"

files = {
    "out_eia__monthly_generators": f"{folder}\\out_eia__monthly_generators.parquet",
    "out_eia923__monthly_generation_fuel_combined": f"{folder}\\out_eia923__monthly_generation_fuel_combined.parquet",
    "out_eia923__monthly_fuel_receipts_costs": f"{folder}\\out_eia923__monthly_fuel_receipts_costs.parquet",
}

# --- LOAD ---
for table_name, file_path in files.items():
    print(f"Loading {table_name}...")
    df = pd.read_parquet(file_path)
    df = df.replace([float('inf'), float('-inf')], None)
    df.to_sql(table_name, con=engine, if_exists="replace", index=False, chunksize=1000)
    print(f"Done: {table_name} — {len(df)} rows loaded")
    
print("All tables loaded successfully.")