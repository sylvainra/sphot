# Générateur CSV SPHOT

Ce paquet contient :
- `sphot_template.csv` : modèle de colonnes issu de ta feuille.
- `generer_csv_sphot_depuis_data_gouv.py` : script de transformation vers des CSV par département.

## Source officielle recommandée

Jeu de données : Données de rapportage de la saison balnéaire  
Ressource à utiliser : `liste des sites de baignade saison 2025 opendata.csv`

## Utilisation

1. Télécharge le CSV officiel depuis data.gouv.fr.
2. Lance :

```bash
python generer_csv_sphot_depuis_data_gouv.py --input liste-des-sites-de-baignade-saison-2025-opendata.csv --output sphot_csv_par_departement
```

ou, si ton ordinateur accède bien à data.gouv.fr :

```bash
python generer_csv_sphot_depuis_data_gouv.py --download --output sphot_csv_par_departement
```

## Prudence sur `typeSphot`

Le fichier officiel national identifie les sites contrôlés et leurs coordonnées.
Il ne fournit pas toujours le niveau exact `LAC`, `RIVIÈRE`, `FLEUVE`, `BARRAGE`, `CASCADE`, `PISCINE NATURELLE`.
Le script ne force donc pas un type terrestre incertain.
