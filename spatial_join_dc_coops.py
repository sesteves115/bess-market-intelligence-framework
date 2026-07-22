import geopandas as gpd
import pandas as pd
from pathlib import Path
from rapidfuzz import process, fuzz

# --- PATHS ---
hifld_path = r"C:\Users\seuni\Downloads\239091-V2\electric-retail-service-territories-shapefile\hifld_cooperatives_only.geojson"
atlas_path = r"C:\Users\seuni\OneDrive\Documentos\Job Applications\capstone project\PUDL tables\Data Center Raw\im3_open_source_data_center_atlas_v2026.02.09\im3_open_source_data_center_atlas_v2026.02.09.csv"
drilldown_path = r"C:\Users\seuni\OneDrive\Documentos\Job Applications\capstone project\PUDL tables\Cooperatives\Final\module_cooperative_drilldown.csv"
output_path = r"C:\Users\seuni\OneDrive\Documentos\Job Applications\capstone project\PUDL tables\Cooperatives\cooperatives and data centers\dc_in_coop_territory.csv"
output_deduped_path = r"C:\Users\seuni\OneDrive\Documentos\Job Applications\capstone project\PUDL tables\Cooperatives\cooperatives and data centers\dc_in_coop_territory_deduped.csv"

# --- STEP 1: Load HIFLD cooperative polygons ---
print("Loading HIFLD cooperative polygons...")
hifld = gpd.read_file(hifld_path)
print(f"HIFLD cooperative polygons: {len(hifld)}")

# --- STEP 2: Load DC atlas ---
print("\nLoading DC atlas...")
atlas = pd.read_csv(atlas_path)
atlas = atlas.dropna(subset=['lat', 'lon'])
atlas_gdf = gpd.GeoDataFrame(
    atlas,
    geometry=gpd.points_from_xy(atlas['lon'], atlas['lat']),
    crs='EPSG:4326'
)
print(f"DC facilities with coordinates: {len(atlas_gdf)}")

if hifld.crs != atlas_gdf.crs:
    hifld = hifld.to_crs(atlas_gdf.crs)

# --- STEP 3: Spatial join ---
print("\nRunning spatial join...")
joined = gpd.sjoin(atlas_gdf, hifld[['NAME', 'STATE', 'geometry']],
                   how='left', predicate='within')

in_territory = joined[joined['NAME'].notna()]

# --- FIX: Deduplicate so each facility is counted only once ---
# If a facility falls inside overlapping cooperative boundaries
# it would otherwise be counted multiple times. Keep first match only.
print(f"Facilities before deduplication: {len(in_territory)}")
in_territory = in_territory.drop_duplicates(subset=['id'])
print(f"Facilities after deduplication: {len(in_territory)}")

print(f"Facilities matched to cooperative territory: {len(in_territory)}")
print(f"Facilities in IOU or unmatched territory: {joined['NAME'].isna().sum()}")

# --- STEP 4: Aggregate by cooperative ---
print("\nAggregating by cooperative...")
agg = in_territory.groupby(['NAME', 'STATE']).agg(
    dc_facility_count=('id', 'count'),
    dc_sqft_in_territory=('sqft', 'sum')
).reset_index()
agg['dc_sqft_in_territory'] = agg['dc_sqft_in_territory'].fillna(0).astype(int)
print(f"Cooperatives with at least one data center: {len(agg)}")

# --- STEP 5: Load drilldown and match ---
print("\nLoading drilldown table...")
drilldown = pd.read_csv(drilldown_path)
print(f"Drilldown cooperatives: {len(drilldown)}")

# Normalize both to uppercase for matching
drilldown['name_upper'] = drilldown['utility_name_eia'].str.upper().str.strip()
drilldown_names_upper = drilldown['name_upper'].tolist()

def fuzzy_match(name, choices, threshold=60):
    name_clean = name.upper().strip()
    result = process.extractOne(name_clean, choices, scorer=fuzz.token_sort_ratio)
    if result and result[1] >= threshold:
        return result[0]
    return None

print("\nMatching HIFLD names to EIA names...")
agg['name_upper'] = agg['NAME'].apply(
    lambda x: fuzzy_match(x, drilldown_names_upper)
)

unmatched = agg[agg['name_upper'].isna()]
print(f"Unmatched after fuzzy join: {len(unmatched)}")
if len(unmatched) > 0:
    print("Unmatched HIFLD names:")
    for name in unmatched['NAME'].tolist():
        print(f"  {name}")

# Join back via normalized name
agg_matched = agg[agg['name_upper'].notna()].copy()
result = drilldown.merge(
    agg_matched[['name_upper', 'dc_facility_count', 'dc_sqft_in_territory']],
    on='name_upper',
    how='left'
)

result['dc_facility_count'] = result['dc_facility_count'].fillna(0).astype(int)
result['dc_sqft_in_territory'] = result['dc_sqft_in_territory'].fillna(0).astype(int)

final = result[['utility_id_eia', 'utility_name_eia', 'state', 'dc_facility_count', 'dc_sqft_in_territory']].copy()

print(f"\nFinal rows: {len(final)}")
print(f"Cooperatives with dc_facility_count > 0: {(final['dc_facility_count'] > 0).sum()}")
print(f"\nTop 10 by facility count:")
print(final.nlargest(10, 'dc_facility_count')[['utility_name_eia', 'state', 'dc_facility_count', 'dc_sqft_in_territory']].to_string())

# --- STEP 6: Save raw output ---
final.to_csv(output_path, index=False)
print(f"\nSaved raw output to: {output_path}")

# --- STEP 7: Deduplicate by utility_id_eia for Power BI ---
print("\nDeduplicating by utility_id_eia for Power BI...")
deduped = final.groupby('utility_id_eia', as_index=False).agg(
    utility_name_eia=('utility_name_eia', 'first'),
    state=('state', 'first'),
    dc_facility_count=('dc_facility_count', 'sum'),
    dc_sqft_in_territory=('dc_sqft_in_territory', 'sum')
)

print(f"Rows before dedup: {len(final)}")
print(f"Rows after dedup: {len(deduped)}")
print(f"Cooperatives with dc_facility_count > 0: {(deduped['dc_facility_count'] > 0).sum()}")

deduped.to_csv(output_deduped_path, index=False)
print(f"\nSaved deduped output to: {output_deduped_path}")