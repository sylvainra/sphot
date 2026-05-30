import csv
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore


BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent.parent
DATA_DIR = PROJECT_DIR / "data" / "pays"
SERVICE_ACCOUNT_PATH = BASE_DIR / "serviceAccountKey.json"


def clean(value):
    if value is None:
        return ""
    return str(value).strip()


def to_float(value):
    value = clean(value).replace(",", ".")
    if not value:
        return 0.0
    try:
        return float(value)
    except ValueError:
        return 0.0


if not DATA_DIR.exists():
    raise FileNotFoundError(f"Dossier data/pays introuvable : {DATA_DIR}")

if not SERVICE_ACCOUNT_PATH.exists():
    raise FileNotFoundError(
        "Fichier serviceAccountKey.json introuvable dans tools/import_spots"
    )


if not firebase_admin._apps:
    cred = credentials.Certificate(str(SERVICE_ACCOUNT_PATH))
    firebase_admin.initialize_app(cred)

db = firestore.client()

csv_files = sorted(DATA_DIR.rglob("*.csv"))

# On ignore volontairement les sauvegardes type longeville_sur_mer1.csv
csv_files = [
    csv_path for csv_path in csv_files
    if not csv_path.stem.endswith("1")
]

if not csv_files:
    raise FileNotFoundError(f"Aucun CSV trouvé dans : {DATA_DIR}")

total_count = 0

for csv_path in csv_files:
    print(f"Import CSV : {csv_path}")

    with open(csv_path, mode="r", encoding="utf-8-sig", newline="") as file:
        reader = csv.DictReader(file)

        count = 0

        for row in reader:
            doc_id = clean(row.get("idSphot")) or clean(row.get("nomSphot"))

            if not doc_id:
                continue

            data = {
                "idSphot": clean(row.get("idSphot")),
                "pays": clean(row.get("pays")),
                "region": clean(row.get("region")),
                "departement": clean(row.get("departement")),
                "ville": clean(row.get("ville")),
                "villeLat": to_float(row.get("villeLat")),
                "villeLng": to_float(row.get("villeLng")),
                "nomSecours": clean(row.get("nomSecours")),
                "nomSphot": clean(row.get("nomSphot")),
                "sphotLat": to_float(row.get("sphotLat")),
                "sphotLng": to_float(row.get("sphotLng")),
                "typeSphot": clean(row.get("typeSphot")),
                "natureSphot": clean(row.get("natureSphot")),
                "adresseWebcam": clean(row.get("adresseWebcam")),
                "arretesMunicipaux": clean(row.get("arretesMunicipaux")),
                "equipement": clean(row.get("equipement")),
                "labelSphot": clean(row.get("labelSphot")),
                "accesPmr": clean(row.get("accesPmr")),
                "moyenPmr": clean(row.get("moyenPmr")),
                "labelPmr": clean(row.get("labelPmr")),
                "activite": clean(row.get("activite")),
                "commerce": clean(row.get("commerce")),
                "source": "csv",
                "csvPath": str(csv_path.relative_to(PROJECT_DIR)).replace("\\", "/"),
            }

            db.collection("spots").document(doc_id).set(data)
            count += 1
            total_count += 1

        print(f"  → {count} SPHOTs importés")

print(f"Import terminé : {total_count} SPHOTs importés dans Firestore")