# SPHOT — pilote réel de récupération de mot de passe (23/10/2026)

## Objectif et limites

Tester **un seul compte Sauveteur de démonstration**, avec une véritable
adresse email, dans `sphot-ab80b`. Ce projet Firebase est également celui de
production : seuls les endpoints de test sont isolés, **pas la base Firestore**.

- Ne jamais utiliser le compte d'un sauveteur actuellement en service : le test
  modifie réellement son mot de passe dans `sauveteurAccounts/{login}`.
- Ne jamais utiliser un compte Super Admin.
- Aucune nouvelle application Firebase et aucun nouveau site Hosting à créer.
- Ne pas remplacer la version publiée de `sphot-advertiser-test` : utiliser
  **uniquement un canal d'aperçu** de ce site existant.
- Ne pas déployer les fonctions de connexion de production :
  `loginSauveteur`, `loginAdmin`, `loginAdvertiser`, etc.
- La branche d'essai ne doit pas être fusionnée dans `main` à cette étape.

## Préparation du compte

Choisir un compte `sauveteurAccounts/{login}` **réservé aux essais**, de statut
`ACTIVE`, ayant une adresse email réellement accessible et, si nécessaire, une
affectation de démonstration valide. Ne transmettre aucun mot de passe ni lien
secret de récupération dans le chat ou dans Git.

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
   SPHOT_PASSWORD_PILOT_URL=https://sphot-advertiser-test--password-pilot-XXXXX.web.app
   SPHOT_PASSWORD_PILOT_EXPIRES_AT=2026-10-26T18:00:00Z
   ```

   Adapter la date d'expiration (UTC), **au maximum 14 jours dans le futur**.
   Le pilote est inactif si l'un de ces trois paramètres est manquant, invalide
   ou expiré. L'URL doit correspondre exactement à celle du canal d'aperçu.

5. Déployer **uniquement** ces trois nouvelles Cloud Functions :

   ```bash
   firebase deploy --only functions:loginSauveteurPilot,functions:requestSphotPasswordRecoveryPilot,functions:completeSphotPasswordRecoveryPilot --project sphot-ab80b
   ```

   Les URLs et noms de fonctions existants restent inchangés.

## Essai unique à réaliser

Sur l'URL d'aperçu :

1. Entrer **l'identifiant Sauveteur pilote**, puis cliquer sur
   « Mot de passe oublié ? ».
2. Demander un nouveau mot de passe et vérifier la réception de **l'email
   réel** sur la boîte associée.
3. Ouvrir le lien d'aperçu reçu et définir un nouveau mot de passe conforme.
4. Vérifier la confirmation de modification, puis se connecter avec **le
   nouveau** mot de passe : connexion du compte pilote acceptée.
5. Vérifier que l'ancien mot de passe est refusé et que le lien utilisé une
   seconde fois échoue.
6. Vérifier qu'aucun compte non pilote, compte Annonceur, Admin ou Super Admin
   ne peut utiliser les fonctions pilote.

Ce test valide le parcours **Sauveteur** et les mécanismes communs de
récupération, mais ne remplace pas une vérification réelle des branchements
propres aux autres espaces lors de leur publication.

## Arrêt du pilote

Modifier `SPHOT_PASSWORD_PILOT_EXPIRES_AT` pour une date passée et redéployer
les **mêmes trois fonctions seulement**. Les appels pilotes refuseront toute
connexion ou réinitialisation. Laisser expirer le canal d'aperçu Firebase.
Ne pas supprimer d'autres fonctions, fichiers, utilisateurs ou sites Hosting.

## Vérifications effectuées dans l'environnement de développement

- Tests Node de récupération de mot de passe pilote et normal : réussis.
- ESLint backend : réussi.
- Import Node de `functions/index.js` avec les trois nouveaux exports : réussi.
- Flutter SDK, Firebase CLI et authentification Firebase : non disponibles
  ici. Aucun déploiement, email réel ou essai de connexion sur serveur n'a été
  effectué depuis cet environnement.
