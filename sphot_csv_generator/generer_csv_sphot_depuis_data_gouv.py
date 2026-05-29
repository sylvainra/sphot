#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Générateur CSV SPHOT département par département.

Objectif :
- partir du fichier officiel "liste des sites de baignade" data.gouv.fr ;
- produire un CSV par département/territoire au format SPHOT :
  idSphot,pays,region,departement,departementLat,departementLng,ville,villeLat,villeLng,
  nomSecours,nomSphot,sphotLat,sphotLng,typeSphot

Important :
- le statut de baignade n'est volontairement pas traité ici ;
- nomSecours est laissé vide quand il n'est pas dans la source ;
- typeSphot est déduit prudemment :
  * eau de mer / eau salée -> ACCÈS PLAGE
  * eau douce -> laissé vide si la source ne distingue pas lac/rivière/fleuve/barrage/cascade/piscine naturelle.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import unicodedata
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen, Request

HEADERS_SPHOT = [
    "idSphot","pays","region","departement","departementLat","departementLng",
    "ville","villeLat","villeLng","nomSecours","nomSphot","sphotLat","sphotLng","typeSphot"
]

# Source officielle : Données de rapportage de la saison balnéaire.
# Télécharger la ressource "liste des sites de baignade saison 2025 opendata.csv"
# depuis : https://www.data.gouv.fr/datasets/donnees-de-rapportage-de-la-saison-balneaire-1
DATA_GOUV_RESOURCE_URL = "https://www.data.gouv.fr/api/1/datasets/r/27c2535a-4ba9-4f48-9ba5-e5d6ca97f750"

# Chef-lieu / préfecture : coordonnées à compléter progressivement si tu veux 100 % local.
# Le script peut fonctionner sans ces valeurs : les colonnes resteront vides.
PREFECTURES_LAT_LNG = {
    "01": ("Bourg-en-Bresse", "46.2052", "5.2255"),
    "02": ("Laon", "49.5641", "3.6244"),
    "03": ("Moulins", "46.5689", "3.3344"),
    "04": ("Digne-les-Bains", "44.0920", "6.2356"),
    "05": ("Gap", "44.5596", "6.0798"),
    "06": ("Nice", "43.7102", "7.2620"),
    "07": ("Privas", "44.7353", "4.5990"),
    "08": ("Charleville-Mézières", "49.7716", "4.7207"),
    "09": ("Foix", "42.9639", "1.6054"),
    "10": ("Troyes", "48.2973", "4.0744"),
    "11": ("Carcassonne", "43.2130", "2.3491"),
    "12": ("Rodez", "44.3494", "2.5759"),
    "13": ("Marseille", "43.2965", "5.3698"),
    "14": ("Caen", "49.1829", "-0.3707"),
    "15": ("Aurillac", "44.9306", "2.4440"),
    "16": ("Angoulême", "45.6484", "0.1562"),
    "17": ("La Rochelle", "46.1603", "-1.1511"),
    "18": ("Bourges", "47.0810", "2.3988"),
    "19": ("Tulle", "45.2678", "1.7707"),
    "21": ("Dijon", "47.3220", "5.0415"),
    "22": ("Saint-Brieuc", "48.5139", "-2.7658"),
    "23": ("Guéret", "46.1700", "1.8718"),
    "24": ("Périgueux", "45.1840", "0.7211"),
    "25": ("Besançon", "47.2378", "6.0241"),
    "26": ("Valence", "44.9334", "4.8924"),
    "27": ("Évreux", "49.0270", "1.1514"),
    "28": ("Chartres", "48.4439", "1.4890"),
    "29": ("Quimper", "47.9975", "-4.0979"),
    "2A": ("Ajaccio", "41.9192", "8.7386"),
    "2B": ("Bastia", "42.6973", "9.4509"),
    "30": ("Nîmes", "43.8367", "4.3601"),
    "31": ("Toulouse", "43.6047", "1.4442"),
    "32": ("Auch", "43.6465", "0.5867"),
    "33": ("Bordeaux", "44.8378", "-0.5792"),
    "34": ("Montpellier", "43.6119", "3.8772"),
    "35": ("Rennes", "48.1173", "-1.6778"),
    "36": ("Châteauroux", "46.8114", "1.6868"),
    "37": ("Tours", "47.3941", "0.6848"),
    "38": ("Grenoble", "45.1885", "5.7245"),
    "39": ("Lons-le-Saunier", "46.6744", "5.5538"),
    "40": ("Mont-de-Marsan", "43.8911", "-0.5000"),
    "41": ("Blois", "47.5861", "1.3359"),
    "42": ("Saint-Étienne", "45.4397", "4.3872"),
    "43": ("Le Puy-en-Velay", "45.0439", "3.8850"),
    "44": ("Nantes", "47.2184", "-1.5536"),
    "45": ("Orléans", "47.9029", "1.9093"),
    "46": ("Cahors", "44.4475", "1.4400"),
    "47": ("Agen", "44.2049", "0.6206"),
    "48": ("Mende", "44.5180", "3.5016"),
    "49": ("Angers", "47.4784", "-0.5632"),
    "50": ("Saint-Lô", "49.1157", "-1.0907"),
    "51": ("Châlons-en-Champagne", "48.9567", "4.3650"),
    "52": ("Chaumont", "48.1111", "5.1395"),
    "53": ("Laval", "48.0707", "-0.7734"),
    "54": ("Nancy", "48.6921", "6.1844"),
    "55": ("Bar-le-Duc", "48.7726", "5.1611"),
    "56": ("Vannes", "47.6582", "-2.7608"),
    "57": ("Metz", "49.1193", "6.1757"),
    "58": ("Nevers", "46.9896", "3.1590"),
    "59": ("Lille", "50.6292", "3.0573"),
    "60": ("Beauvais", "49.4300", "2.0800"),
    "61": ("Alençon", "48.4329", "0.0913"),
    "62": ("Arras", "50.2910", "2.7775"),
    "63": ("Clermont-Ferrand", "45.7772", "3.0870"),
    "64": ("Pau", "43.2951", "-0.3708"),
    "65": ("Tarbes", "43.2329", "0.0781"),
    "66": ("Perpignan", "42.6887", "2.8948"),
    "67": ("Strasbourg", "48.5734", "7.7521"),
    "68": ("Colmar", "48.0794", "7.3585"),
    "69": ("Lyon", "45.7640", "4.8357"),
    "70": ("Vesoul", "47.6206", "6.1554"),
    "71": ("Mâcon", "46.3069", "4.8287"),
    "72": ("Le Mans", "48.0061", "0.1996"),
    "73": ("Chambéry", "45.5646", "5.9178"),
    "74": ("Annecy", "45.8992", "6.1294"),
    "75": ("Paris", "48.8566", "2.3522"),
    "76": ("Rouen", "49.4431", "1.0993"),
    "77": ("Melun", "48.5399", "2.6608"),
    "78": ("Versailles", "48.8014", "2.1301"),
    "79": ("Niort", "46.3237", "-0.4648"),
    "80": ("Amiens", "49.8941", "2.2958"),
    "81": ("Albi", "43.9251", "2.1486"),
    "82": ("Montauban", "44.0221", "1.3529"),
    "83": ("Toulon", "43.1242", "5.9280"),
    "84": ("Avignon", "43.9493", "4.8055"),
    "85": ("La Roche-sur-Yon", "46.6705", "-1.4264"),
    "86": ("Poitiers", "46.5802", "0.3404"),
    "87": ("Limoges", "45.8336", "1.2611"),
    "88": ("Épinal", "48.1744", "6.4494"),
    "89": ("Auxerre", "47.7982", "3.5738"),
    "90": ("Belfort", "47.6396", "6.8638"),
    "91": ("Évry-Courcouronnes", "48.6298", "2.4418"),
    "92": ("Nanterre", "48.8924", "2.2153"),
    "93": ("Bobigny", "48.9086", "2.4397"),
    "94": ("Créteil", "48.7904", "2.4556"),
    "95": ("Cergy", "49.0356", "2.0603"),
    "971": ("Basse-Terre", "15.9985", "-61.7255"),
    "972": ("Fort-de-France", "14.6161", "-61.0588"),
    "973": ("Cayenne", "4.9224", "-52.3135"),
    "974": ("Saint-Denis", "-20.8823", "55.4504"),
    "976": ("Mamoudzou", "-12.7806", "45.2279"),
}

def norm(s: str | None) -> str:
    if s is None:
        return ""
    s = str(s).strip()
    return "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn").lower()

def first(row: dict, *names: str) -> str:
    # match exact, normalized exact, then contains
    keys = list(row.keys())
    by_norm = {norm(k): k for k in keys}
    for name in names:
        if name in row and row[name] not in (None, ""):
            return str(row[name]).strip()
        nk = norm(name)
        if nk in by_norm and row[by_norm[nk]] not in (None, ""):
            return str(row[by_norm[nk]]).strip()
    for name in names:
        nk = norm(name)
        for k in keys:
            if nk in norm(k) and row[k] not in (None, ""):
                return str(row[k]).strip()
    return ""

def detect_delimiter(path: Path) -> str:
    sample = path.read_text(encoding="utf-8-sig", errors="replace")[:4096]
    try:
        return csv.Sniffer().sniff(sample, delimiters=";,|\t").delimiter
    except Exception:
        return ";"

def download(url: str, dest: Path):
    req = Request(url, headers={"User-Agent": "SPHOT CSV generator/1.0"})
    with urlopen(req, timeout=60) as r:
        dest.write_bytes(r.read())

def type_sphot(row: dict) -> str:
    text = " ".join(str(v) for v in row.values() if v is not None)
    n = norm(text)
    if any(x in n for x in ["eau de mer", "mer", "ocean", "salée", "salee", "littoral"]):
        return "ACCÈS PLAGE"
    # Prudence : ne pas inventer lac/rivière/fleuve/barrage/cascade si la source ne le dit pas.
    if "lac" in n or "etang" in n or "étang" in n or "plan d'eau" in n:
        return "LAC"
    if "riviere" in n or "rivière" in n:
        return "RIVIÈRE"
    if "fleuve" in n or "seine" in n or "loire" in n or "rhone" in n or "garonne" in n:
        return "FLEUVE"
    if "barrage" in n or "retenue" in n:
        return "BARRAGE"
    if "cascade" in n:
        return "CASCADE"
    if "lagon" in n:
        return "LAGON"
    if "piscine naturelle" in n or "bassin naturel" in n:
        return "PISCINE NATURELLE"
    return ""

def clean_code_dept(code: str) -> str:
    code = str(code or "").strip().upper()
    code = re.sub(r"\.0$", "", code)
    if code.isdigit() and len(code) <= 2:
        return code.zfill(2)
    return code

def safe_filename(s: str) -> str:
    s = norm(s).upper()
    s = re.sub(r"[^A-Z0-9]+", "_", s).strip("_")
    return s or "INCONNU"

def build(input_csv: Path, output_dir: Path):
    output_dir.mkdir(parents=True, exist_ok=True)
    delimiter = detect_delimiter(input_csv)

    with input_csv.open("r", encoding="utf-8-sig", errors="replace", newline="") as f:
        rows = list(csv.DictReader(f, delimiter=delimiter))

    out_by_dep: dict[str, list[dict]] = {}

    for idx, row in enumerate(rows, start=1):
        code_dep = clean_code_dept(first(row, "code_departement", "cdeDpt", "departement_code", "Code département", "DPT", "dpt"))
        dep = first(row, "departement", "Département", "libelle_departement", "nom_departement", "libelleDpt")
        region = first(row, "region", "Région", "libelle_region", "nom_region", "libelleReg")
        ville = first(row, "commune", "Commune", "nom_commune", "libelleCommune", "libelle_commune", "nomCommune")
        nom = first(row, "nom_site", "site", "nomSite", "Libellé du site", "libelle_site", "nom de la baignade", "Nom du site")
        lat = first(row, "latitude", "lat", "Latitude", "sphotLat", "coord_y", "Y")
        lng = first(row, "longitude", "lon", "lng", "Longitude", "sphotLng", "coord_x", "X")

        if not nom and not lat and not lng:
            continue

        pref = PREFECTURES_LAT_LNG.get(code_dep, ("", "", ""))
        dep_lat, dep_lng = pref[1], pref[2]

        out = {
            "idSphot": f"FR-{code_dep or 'XXX'}-{len(out_by_dep.get(code_dep, []))+1:04d}",
            "pays": "France",
            "region": region,
            "departement": dep or code_dep,
            "departementLat": dep_lat,
            "departementLng": dep_lng,
            "ville": ville,
            "villeLat": "",
            "villeLng": "",
            "nomSecours": "",
            "nomSphot": nom,
            "sphotLat": lat.replace(",", "."),
            "sphotLng": lng.replace(",", "."),
            "typeSphot": type_sphot(row),
        }
        out_by_dep.setdefault(code_dep or "INCONNU", []).append(out)

    for code_dep, dep_rows in sorted(out_by_dep.items()):
        dep_name = dep_rows[0].get("departement") or code_dep
        path = output_dir / f"sphot_{code_dep}_{safe_filename(dep_name)}.csv"
        with path.open("w", encoding="utf-8-sig", newline="") as f:
            w = csv.DictWriter(f, fieldnames=HEADERS_SPHOT, delimiter=",")
            w.writeheader()
            w.writerows(dep_rows)

    # global file
    all_path = output_dir / "sphot_FRANCE_TOUS_DEPARTEMENTS.csv"
    with all_path.open("w", encoding="utf-8-sig", newline="") as f:
        w = csv.DictWriter(f, fieldnames=HEADERS_SPHOT, delimiter=",")
        w.writeheader()
        for dep_rows in out_by_dep.values():
            w.writerows(dep_rows)

    print(f"{sum(len(v) for v in out_by_dep.values())} lignes générées dans {len(out_by_dep)} CSV départementaux.")
    print(f"Dossier : {output_dir}")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--input", help="CSV officiel téléchargé depuis data.gouv.fr")
    p.add_argument("--download", action="store_true", help="Tente de télécharger la ressource officielle data.gouv.fr")
    p.add_argument("--output", default="sphot_csv_par_departement", help="Dossier de sortie")
    args = p.parse_args()

    if args.download:
        src = Path("liste-des-sites-de-baignade-saison-2025-opendata.csv")
        download(DATA_GOUV_RESOURCE_URL, src)
    elif args.input:
        src = Path(args.input)
    else:
        print("Indique --input fichier.csv ou --download", file=sys.stderr)
        sys.exit(2)

    build(src, Path(args.output))

if __name__ == "__main__":
    main()
