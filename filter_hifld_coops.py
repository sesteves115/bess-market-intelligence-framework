import json
from pathlib import Path

input_path = Path(r"C:\Users\seuni\Downloads\239091-V2\electric-retail-service-territories-shapefile\electric-retail-service-territories-geojson.geojson")
output_path = Path(r"C:\Users\seuni\Downloads\239091-V2\hifld_cooperatives_only.geojson")

print("Reading full GeoJSON...")
with open(input_path, encoding='utf-8') as f:
    data = json.load(f)

print(f"Total features: {len(data['features'])}")

coops = [f for f in data['features']
         if str(f.get('properties', {}).get('TYPE', '')).upper() == 'COOPERATIVE']

print(f"Cooperative features: {len(coops)}")

output = {
    "type": "FeatureCollection",
    "features": coops
}

with open(output_path, 'w', encoding='utf-8') as f:
    json.dump(output, f)

print(f"Saved to: {output_path}")