import csv
import json
from pathlib import Path

# Dossier du script
BASE_DIR = Path(__file__).resolve().parent

# Cherche automatiquement le premier fichier CSV dans tools/import_spots
csv_files = list(BASE_DIR.glob("*.csv"))

if not csv_files:
    raise FileNotFoundError("Aucun fichier .csv trouvé dans tools/import_spots")

CSV_PATH = csv_files[0]
OUTPUT_PATH = BASE_DIR.parent.parent / "assets" / "data" / "spots.json"

OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)

spots = []

with open(CSV_PATH, mode="r", encoding="utf-8-sig", newline="") as file:
    reader = csv.DictReader(file)

    for row in reader:
        clean_row = {}

        for key, value in row.items():
            if key is None:
                continue

            clean_key = key.strip()
            clean_value = value.strip() if value else ""

            clean_row[clean_key] = clean_value

        spots.append(clean_row)

with open(OUTPUT_PATH, mode="w", encoding="utf-8") as file:
    json.dump(spots, file, ensure_ascii=False, indent=2)

print(f"CSV importé : {CSV_PATH.name}")
print(f"{len(spots)} spots exportés vers : {OUTPUT_PATH}")