# SPHOT ADMIN — raccordement visuel du cycle CARTE fictif C4 TEST

Étape de **lecture seule**, sans nouvelle commande Odoo, aucun nouveau
paiement Stripe, aucun droit créé ou modifié dans Firestore.

Le test carte précédemment validé est distinct du compte ADMIN connecté :

- Firestore : `sphot-c4-test-20261029` seulement pour le dossier fictif ;
- Odoo : `sphot_publicitaire_checkout_test` uniquement ;
- référence : `SPHOT-ADM-TEST-68D69D07E8DDE668` ;
- deux postes entièrement fictifs ; total 898,00 € HT / 1 077,60 € TTC ;
- facture Stripe TEST payée et rapprochée, puis activation déjà vérifiée.

Le nouveau bouton **VÉRIFIER CARTE FICTIVE C4 TEST**, dans l'étape 05
du panneau `ABONNEMENT & PAIEMENT`, relit côté serveur la commande, la
facture, la preuve Stripe et la projection Firestore. Il ne transmet aucun
SIREN/SIRET ni sélection réelle du navigateur. Une session Firebase ADMIN
est obligatoire. Le bouton **CONFIRMER MA COMMANDE** reste désactivé
jusqu'au raccordement légal et fiscal du dossier réel.

## Installation sur Windows (PowerShell dans le dossier `sphot`)

1. Vérifier le SHA256 de l'archive reçue avant extraction. Ne jamais remplacer
   les fichiers existants sans contrôle préalable. Les deux nouveaux fichiers
   JS et test + ce README s'ajoutent ; le patch modifie les trois fichiers
   existants, en préservant les autres changements.
2. `git apply --check .\sphot_admin_card_status_READONLY_TEST.patch`, puis
   `git apply .\sphot_admin_card_status_READONLY_TEST.patch` seulement si
   le contrôle a réussi. Si le patch échoue, **arrêter** et fournir le
   résultat de `git status --short` et `git apply --check --verbose`.
3. Exécuter les tests sans connexion réseau :

   ```powershell
   node --test functions/test/odoo_admin_card_test_status_readonly.test.js functions/test/odoo_admin_live_readonly_preflight.test.js functions/test/odoo_admin_card_test_cycle.test.js
   git diff --check
   ```

## Démarrage local

Premier terminal, depuis `C:\Users\surfS\sphot`. Vérifier l'ADC C4 TEST
déjà configuré et la clé Odoo TEST présente **dans ce terminal**.

```powershell
$env:GCLOUD_PROJECT = 'sphot-c4-test-20261029'
$env:GOOGLE_CLOUD_PROJECT = 'sphot-c4-test-20261029'
$env:SPHOT_ADMIN_ODOO_READONLY_PREFLIGHT = 'true'
$env:SPHOT_ADMIN_ODOO_TEST_CARD_STATUS_READONLY = 'true'
$env:SPHOT_ADMIN_ODOO_TEST_FIXTURE_READONLY = 'true'

if (-not $env:SPHOT_ODOO_LOCAL_API_KEY) {
    $k = Read-Host 'Clé API Odoo TEST' -AsSecureString
    $env:SPHOT_ODOO_LOCAL_API_KEY = (
        New-Object System.Net.NetworkCredential('', $k)
    ).Password
    Remove-Variable k
}

node functions/local/start_admin_odoo_readonly.js
```

Si la passerelle écoute déjà sur `127.0.0.1:8768`, l'arrêter au préalable
avec Ctrl+C puis la relancer. Ne pas démarrer deux serveurs sur le même port.

Second terminal, toujours dans `sphot` :

```powershell
flutter run -d chrome -t lib/main_web_admin.dart `
  --dart-define=SPHOT_ADMIN_ODOO_TEST_PREFLIGHT_URL=http://127.0.0.1:8768/admin/preflight `
  --dart-define=SPHOT_ADMIN_ODOO_TEST_FIXTURE_READONLY=true `
  --dart-define=SPHOT_ADMIN_ODOO_TEST_CARD_STATUS_READONLY=true
```

Ouvrir `ABONNEMENT & PAIEMENT` > `05 — CONDITIONS ET CONFIRMATION` >
`VÉRIFIER CARTE FICTIVE C4 TEST`. Un résultat vert confirme que les preuves
TEST sont toujours concordantes ; un refus n'entraîne aucune écriture.

Pour arrêter les tests, supprimer les deux `--dart-define` de fixture/statut
au prochain lancement Flutter et arrêter la passerelle locale.

## Limite explicite

Ce contrôle ne rattache **pas** les droits de la fixture C4 TEST à
`adminAccounts`, `admins` ni `subscriptions` de SPHOT production. Le
compte ADMIN réel aux SIREN/SIRET obsolètes nécessite une première revue
Super Admin authentique, la validation du payeur, la fiscalité, la version
des CGV et son acceptation avant toute commande réelle. Aucune de ces
preuves n'est fabriquée ici.
