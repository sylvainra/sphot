# SPHOT — pilote réel de récupération de mot de passe (23/10/2026)

## Objectif et limites

Tester **un compte de démonstration par rôle** (Sauveteur, Admin,
Publicitaire), avec une véritable adresse email, dans `sphot-ab80b`.
Les trois parcours ont ensuite été vérifiés en réel (bilan du 24/10/2026).
Ce projet Firebase est également celui de production :
seuls les endpoints de test sont isolés, **pas la base Firestore**.

- Ne jamais utiliser un compte opérationnel : les essais changent réellement
  les mots de passe dans `sauveteurAccounts/{login}`,
  `adminAccounts/{login}` et `advertiserAccounts/{login}`.
- Ne jamais utiliser un compte Super Admin.
- Aucune nouvelle application Firebase et aucun nouveau site Hosting à créer.
- Ne pas remplacer la version publiée de `sphot-advertiser-test` : utiliser
  **uniquement un canal d'aperçu** de ce site existant.
- Ne pas déployer les fonctions de connexion de production :
  `loginSauveteur`, `loginAdmin`, `loginAdvertiser`, etc.
- Durant la phase pilote, ne pas fusionner dans `main` avant validation
  des trois parcours et revue des impacts sur les fonctions existantes.

## Préparation du compte

Vérifier que les trois comptes sont **réservés aux essais**, de statut
`ACTIVE`, avec une adresse email réellement accessible et les données métier
nécessaires à leur connexion. Leurs identifiants doivent être associés à leur
rôle dans les paramètres Firebase du pilote. Ne transmettre aucun mot de passe
ni lien secret de récupération dans le chat ou dans Git.

## Publication contrôlée de la version pilote

Prérequis sur le poste de travail autorisé : Flutter, Firebase CLI, accès
Firebase déploiement et branche contenant ce pilote. Depuis la racine SPHOT :

1. Vérifier `git status`, la branche et les différences avec `main`.
2. Construire une version Web dont **seule cette compilation** utilise les
   endpoints pilote :

   ```bash
   flutter build web --release -t lib/main.dart --dart-define=SPHOT_PASSWORD_PILOT=true
   ```

3. Déployer **exclusivement** sur le canal d'aperçu du site existant :

   ```bash
   firebase hosting:channel:deploy password-pilot --only advertiser --config firebase.password-pilot.json --project sphot-ab80b
   ```

   Noter l'URL d'aperçu réellement retournée par Firebase, du type
   `https://sphot-advertiser-test--password-pilot-XXXXX.web.app`.

4. Renseigner **sur ce poste seulement** les paramètres d'exécution dans
   `functions/.env.sphot-ab80b` (ignoré par Git). Si le fichier contient déjà
   d'autres paramètres, les conserver :

   ```dotenv
   SPHOT_PASSWORD_PILOT_LOGIN=identifiant-du-compte-de-test
   SPHOT_PASSWORD_PILOT_ADMIN_LOGIN=identifiant-admin-de-test
   SPHOT_PASSWORD_PILOT_ADVERTISER_LOGIN=identifiant-publicitaire-de-test
   SPHOT_PASSWORD_PILOT_URL=https://sphot-advertiser-test--password-pilot-XXXXX.web.app
   SPHOT_PASSWORD_PILOT_EXPIRES_AT=2026-10-26T18:00:00Z
   ```

   Adapter la date d'expiration (UTC), **au maximum 14 jours dans le futur**.
   Le compte Sauveteur, l'URL et la date d'expiration restent obligatoires.
   Les deux autres comptes ne sont autorisés que si leurs paramètres sont
   renseignés. Si l'URL ou la date est invalide/expirée, l'ensemble du pilote
   est désactivé. L'URL doit correspondre exactement à celle de l'aperçu.

5. Déployer **uniquement** les cinq Cloud Functions du pilote :

   ```bash
   firebase deploy --only "functions:loginSauveteurPilot,functions:loginAdminPilot,functions:loginAdvertiserPilot,functions:requestSphotPasswordRecoveryPilot,functions:completeSphotPasswordRecoveryPilot" --project sphot-ab80b
   ```

   Les URLs et noms de fonctions existants restent inchangés.

## Essai unique à réaliser

Sur l'URL d'aperçu :

1. Entrer **l'identifiant pilote correspondant au rôle**, puis cliquer sur
   « Mot de passe oublié ? ».
2. Demander un nouveau mot de passe et vérifier la réception de **l'email
   réel** sur la boîte associée.
3. Ouvrir le lien d'aperçu reçu et définir un nouveau mot de passe conforme.
4. Vérifier la confirmation de modification, puis se connecter avec **le
   nouveau** mot de passe : connexion du compte pilote acceptée.
5. Vérifier que l'ancien mot de passe est refusé et que le lien utilisé une
   seconde fois échoue.
6. Vérifier qu'aucun compte non pilote, identifiant d'un autre rôle ou Super
   Admin ne peut utiliser les fonctions pilote.

La validation réelle est enregistrée **séparément pour chacun des trois
espaces**. Ne pas déclarer les comptes Admin et Publicitaire validés avant
réception de l'email, changement de mot de passe et reconnexion réussie.

## Arrêt du pilote

Modifier `SPHOT_PASSWORD_PILOT_EXPIRES_AT` pour une date passée et redéployer
les **mêmes cinq fonctions seulement**. Les appels pilotes refuseront toute
connexion ou réinitialisation. Laisser expirer le canal d'aperçu Firebase.
Ne pas supprimer d'autres fonctions, fichiers, utilisateurs ou sites Hosting.

## Vérifications effectuées dans l'environnement de développement

- Ancienne version à un rôle : tests Node et ESLint réussis, premier essai
  réel Sauveteur confirmé par l'utilisateur.
- Nouvelle version à trois rôles : parcours réels confirmés ci-dessous.
- Flutter SDK et Firebase CLI : non disponibles dans l'environnement de
  développement distant. Le déploiement doit être exécuté depuis le poste
  autorisé et vérifié avant toute validation des deux nouveaux parcours.

## Bilan vérifié le 24/10/2026 et préparation de l'intégration

- Sauveteur : réception du mail, nouveau mot de passe et reconnexion
  validés par l'utilisateur.
- Publicitaire : changement du mot de passe et reconnexion validés
  par l'utilisateur.
- Admin : identifiant de connexion identique à son adresse email ;
  reconnaissance Firebase confirmée, mail reçu, changement et reconnexion
  validés par l'utilisateur.
- Super Admin : exclu du dispositif pilote de récupération.
- Déploiements pilotes : canal d'aperçu Hosting et cinq fonctions dédiées,
  sans remplacement des fonctions de connexion en production.
- Révision de la branche testée : `2660da1` ; base `main` : `00514fd`.
- Contrôle local d'intégration : `npm run lint` réussi ; 33 suites sur 34
  passent avec `node --test test/*.test.js`. L'échec de
  `commercial_radius_catalog.test.js` concerne des fichiers tarifaires
  identiques à ceux de `main` et n'est pas lié au chantier mot de passe.
- Limite : le SDK Flutter n'est pas présent dans l'environnement distant.
  Les parcours réels de récupération sont validés, mais les autres actions
  affectées par le renforcement des droits (création, modification,
  suppression de sauveteurs et première connexion) nécessitent une
  vérification de non-régression avant déploiement général.
- La fusion du code dans `main` et le déploiement sur les URLs de production
  sont deux opérations distinctes. Aucun déploiement général ne doit être
  déduit de la seule fusion Git.
