# SPHOT PUBLICITAIRE — Test visuel isolé (19/10/2026)

**Aucun déploiement Firebase, aucun push main, aucune modification de données de production.**

Ce scénario contrôle :
- trois annonces Carte / Premium / Pack dans Firestore Emulator ;
- soumission, approbation simulée et synchronisation transactionnelle réelle via le module Cloud Function ;
- dates, prix et visibilité préservés, historique de changement ;
- projection publique via le même code que la Cloud Function ;
- affichage dans la carte Flutter Web et les six rubriques d'un SPHOT réel,
  en substituant UNIQUEMENT la source de publicité par une API locale.

**Limites :** le bouton Super Admin réel, l'authentification et l'envoi SMTP
ne sont pas exercés par ce test isolé. Aucun email n'est envoyé.
Le visuel local servi par HTTP n'est pas téléversé sur Firebase Storage.

## Prérequis
- Git sur la branche `feature/map-ad-banner-image-web-mobile-20261019`.
- Node.js et dépendances du dossier `functions` installées.
- Firebase CLI (`firebase --version`) et Java (`java -version`).
- Aucun serveur Flutter déjà lancé sur le port 51778.

## Fenêtre PowerShell 1 — Firestore local

```powershell
cd C:\Users\surfS\sphot
firebase emulators:start --config firebase.advertiser-emulator.json --project demo-sphot-publicitaire --only firestore
```

Attendre `All emulators ready!`. Ne pas fermer cette fenêtre.

## Fenêtre PowerShell 2 — Scénario de validation et API locale

```powershell
cd C:\Users\surfS\sphot
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8085'
# Site annoncé par le visuel Surf Shop Atlantique (modifiable).
$env:SPHOT_TEST_DESTINATION_URL = 'https://www.surfshop-atlantique.fr'
node functions/test/advertiser_campaign_emulator_smoke.js

$visuel = Join-Path $env:USERPROFILE 'Downloads\SPHOT_SURF_SHOP_ATLANTIQUE_1800x300.jpg'
if (Test-Path $visuel) {
  $env:SPHOT_TEST_BANNER_FILE = $visuel
} else {
  Write-Host "Bannière introuvable : le test affichera un visuel de remplacement."
}
node functions/test/advertiser_emulator_http.js
```

Résultat attendu : `SUCCESS : campagne de demonstration prete pour l'affichage.`
L'API reste ouverte sur `http://127.0.0.1:8099/advertisements?mode=pack`.

Il est possible d'utiliser une autre image JPG/PNG/WEBP :
`$env:SPHOT_TEST_BANNER_FILE = 'C:\chemin\vers\image.jpg'`
puis relancer le serveur local.

## Fenêtre PowerShell 3 — Flutter Web (en lecture de publicités locales)

```powershell
cd C:\Users\surfS\sphot
flutter run -d chrome --web-port 51778 --dart-define="SPHOT_PUBLIC_ADS_URL=http://127.0.0.1:8099/advertisements?mode=pack" --dart-define=SPHOT_ADS_EMULATOR=true
```

Vérifier la carte, ouvrir LONGE 06, visiter les six rubriques et simuler
un téléphone (Chrome DevTools). Les SPHOTS restent lus depuis Firestore public,
mais les publicités proviennent UNIQUEMENT de l'émulateur.

Pour tester les autres offres, fermer Flutter puis relancer avec :
- `?mode=map` : uniquement Carte (aucune pub dans les fiches)
- `?mode=premium` : uniquement Premium (aucune pub dans la carte)
- `?mode=pack` : Carte et six rubriques de la fiche

## Arrêt

Dans chaque fenêtre PowerShell, faire `Ctrl+C`. Les données fictives de
Firestore Emulator sont éphémères et disparaissent quand l'émulateur s'arrête.

## Important

Cette validation est une **préqualification du rendu** et de la chaîne de
données simulée. Elle ne remplace pas le test authentifié du Super Admin ni le
contrôle de la synchronisation et des emails sur un environnement déployé.

## Critères supplémentaires de validation

- Le bandeau panoramique doit être plus grand sur le site Web que sur mobile.
- **Zone visuelle** : le clic ouvre `SPHOT_TEST_DESTINATION_URL` (site annonceur).
- **Zone orange distincte « CRÉER MON SPHOT PUBLICITAIRE »** : le clic
  ouvre le parcours de création SPHOT, jamais le site annonceur.
- Les six encarts de la fiche utilisent le visuel de la campagne Pack, y
  compris en mode mobile. `SPHOT_ADS_EMULATOR=true` autorise l'image HTTP
  **uniquement** depuis l'adresse locale `127.0.0.1:8099/creative` ;
  les images de production continuent d'exiger HTTPS.
- Après un changement de fichier source, relancer le scénario test et
  redémarrer Flutter pour rafraîchir les listes chargées au lancement.
