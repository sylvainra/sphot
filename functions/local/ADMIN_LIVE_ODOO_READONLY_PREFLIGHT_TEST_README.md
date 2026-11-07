# SPHOT ADMIN — raccordement initial du portail à Odoo TEST

Cette première liaison est **strictement en lecture seule** et fonctionne
sur votre PC via `http://127.0.0.1:8768/admin/preflight`.
Elle ne modifie ni les fichiers SPHOT PUBLICITAIRE, ni la base Firestore,
ni la base Odoo. Aucune fonction Cloud n'est déployée.

## Parcours vérifié

1. Le navigateur Flutter transmet au serveur local un jeton Firebase ID
   et **uniquement** les identifiants des postes sélectionnés.
2. Le serveur identifie le compte avec `verifyIdToken` côté Firebase,
   puis lit les dossiers `adminRequests`, `admins`, `subscriptions` et
   l'archive `adminOdooReviewEvidence` dans **sphot-ab80b**.
3. Il vérifie le territoire, le SIREN/SIRET, le filtre initial du Super Admin
   et l'empreinte de la décision archivée.
4. Il relit chacun des postes sous `territoires/{territoireId}/spots`,
   recalcule les quatre tranches depuis le catalogue ADMIN publié et la
   remise serveur, puis vérifie les quatre produits de la base Odoo TEST.
5. Le résultat affiche le nombre de postes et le prix HT recalculé ;
   il précise **aucune commande/facture/activation créée**.

## Limitations délibérées

- La première preuve Super Admin doit être une archive authentique
  `server_review_archive`. Si elle est absente dans Firebase, le serveur
  **refuse** le précontrôle. Il ne fabrique aucune preuve.
- La fiscalité, les CGV et l'identité du payeur ne sont pas encore vérifiées
  pour la commande : l'émission d'une commande Odoo reste interdite.
- L'authentification locale du serveur requiert une configuration Firebase
  Admin ayant une **autorisation de lecture** sur le projet actuel. Si les
  identifiants Google sont absents ou insuffisants, la lecture est refusée.
  Ne pas copier de clés privées ni contourner ces restrictions.
- Le serveur écoute uniquement sur `127.0.0.1`. Il accepte uniquement
  les origines navigateur locales. La passerelle ne convient pas à un site
  public distant : une architecture serveur hébergée et TLS sera nécessaire
  pour la production.

## Tests sans connexion

```powershell
node --test functions/test/odoo_admin_live_readonly_preflight.test.js
flutter analyze --no-pub lib/web/admin/pages/admin_subscription_panel.dart lib/web/admin/services/admin_odoo_local_preflight_service.dart
```

## Test manuel après validation du code

Dans un terminal VS Code réservé à la passerelle :

```powershell
$k = Read-Host "Cle API Odoo TEST" -AsSecureString
$env:SPHOT_ODOO_LOCAL_API_KEY = (New-Object System.Net.NetworkCredential("", $k)).Password
Remove-Variable k
$env:SPHOT_ADMIN_ODOO_READONLY_PREFLIGHT = 'true'
node functions/local/start_admin_odoo_readonly.js
```

Lors de votre lancement local Flutter Web habituel, ajoutez la définition :

`--dart-define=SPHOT_ADMIN_ODOO_TEST_PREFLIGHT_URL=http://127.0.0.1:8768/admin/preflight`

Sans cette définition, le bouton d'offre reste bloqué comme auparavant.
Seule une session ADMIN Firebase valide pourra effectuer le précontrôle.

## Ensuite

Valider séparément l'habilitation du payeur, la fiscalité et les CGV ; puis
créer/relire la commande Odoo TEST de façon idempotente avant de permettre
une facture unique et la projection Firestore TEST sur preuve vérifiée.
