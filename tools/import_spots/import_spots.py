import csv
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, firestore


BASE_DIR = Path(__file__).resolve().parent
PROJECT_DIR = BASE_DIR.parent.parent
DATA_DIR = PROJECT_DIR / "data" / "pays"
SERVICE_ACCOUNT_PATH = BASE_DIR / "serviceAccountKey.json"


if not DATA_DIR.exists():
    raise FileNotFoundError(f"Dossier data/pays introuvable : {DATA_DIR}")

if not SERVICE_ACCOUNT_PATH.exists():
    raise FileNotFoundError(
        "Fichier serviceAccountKey.json introuvable dans tools/import_spots"
    )


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


if not firebase_admin._apps:
    cred = credentials.Certificate(str(SERVICE_ACCOUNT_PATH))
    firebase_admin.initialize_app(cred)

db = firestore.client()

csv_files = sorted(DATA_DIR.rglob("*.csv"))

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
                "departementLat": to_float(row.get("departementLat")),
                "departementLng": to_float(row.get("departementLng")),
                "ville": clean(row.get("ville")),
                "villeLat": to_float(row.get("villeLat")),
                "villeLng": to_float(row.get("villeLng")),
                "nomSecours": clean(row.get("nomSecours")),
                "nomSphot": clean(row.get("nomSphot")),
                "sphotLat": to_float(row.get("sphotLat")),
                "sphotLng": to_float(row.get("sphotLng")),
                "typeSphot": clean(row.get("typeSphot")),
                "natureSphot": clean(row.get("natureSphot")),
                "equipement": clean(row.get("equipement")),
                "labelPlage": clean(row.get("labelPlage")),
                "accesPmr": clean(row.get("accesPmr")),
                "moyenPmr": clean(row.get("moyenPmr")),
                "labelsPmr": clean(row.get("labelsPmr")),
                "statutBaignade": clean(row.get("statutBaignade")),
                "periode": clean(row.get("periode")),
                "heureDebut": clean(row.get("heureDebut")),
                "heureFin": clean(row.get("heureFin")),
                "couleur": clean(row.get("couleur")),
                "mat": clean(row.get("mat")),
                "temperatureAir": clean(row.get("temperatureAir")),
                "temperatureEau": clean(row.get("temperatureEau")),
                "mareeHaute1": clean(row.get("mareeHaute1")),
                "mareeBasse1": clean(row.get("mareeBasse1")),
                "mareeHaute2": clean(row.get("mareeHaute2")),
                "mareeBasse2": clean(row.get("mareeBasse2")),
                "coef1": clean(row.get("coef1")),
                "coef2": clean(row.get("coef2")),
                "heurePrevision": clean(row.get("heurePrevision")),
                "ciel": clean(row.get("ciel")),
                "mer": clean(row.get("mer")),
                "ventVitesse": clean(row.get("ventVitesse")),
                "ventRafale": clean(row.get("ventRafale")),
                "ventDirection": clean(row.get("ventDirection")),
                "houleHauteur": clean(row.get("houleHauteur")),
                "houlePeriode": clean(row.get("houlePeriode")),
                "uv": clean(row.get("uv")),
                "dangers": clean(row.get("dangers")),
                "commentaire": clean(row.get("commentaire")),
                "ephemeride": clean(row.get("ephemeride")),
                "dicton": clean(row.get("dicton")),
                "activite": clean(row.get("activite")),
                "commerce": clean(row.get("commerce")),
                "dateMaj": clean(row.get("dateMaj")),
                "phone": "",
                "liveFlag": {
                    "flagColor": clean(row.get("couleur")),
                    "flagPosition": clean(row.get("mat")),
                },
                "source": "csv",
                "csvPath": str(csv_path.relative_to(PROJECT_DIR)).replace("\\", "/"),
            }

            db.collection("spots").document(doc_id).set(data)
            count += 1
            total_count += 1

        print(f"  → {count} SPHOTs importés")

print(f"Import terminé : {total_count} SPHOTs importés dans Firestore")