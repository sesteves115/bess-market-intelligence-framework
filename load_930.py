import pandas as pd
import sqlalchemy
from sqlalchemy import create_engine

user = "root"
password = "*Kousei0511*"
host = "localhost"
port = 3306
db_name = "bess_project"

engine = create_engine(f"mysql+pymysql://{user}:{password}@{host}:{port}/{db_name}")

folder = r"C:\Users\seuni\OneDrive\Documentos\Job Applications\capstone project\PUDL tables"

print("Loading out_eia930__hourly_operations...")
df = pd.read_parquet(f"{folder}\\out_eia930__hourly_operations.parquet")
df = df.replace([float('inf'), float('-inf')], None)
df.to_sql("out_eia930__hourly_operations", con=engine, if_exists="replace", index=False, chunksize=1000)
print(f"Done: {len(df)} rows loaded")