# SPHOT — non-régression gestion Sauveteur depuis Flutter sur PC

## Périmètre

Vérifier création, identifiants par email, affectations, première connexion,
changement du mot de passe provisoire et suppression d'un **seul compte jetable**.
Point de départ : `main` au commit `355addb`, sans remplacer les quatre
fonctions de production actuellement déployées.

Le projet Firebase `sphot-ab80b` contient les données réelles du projet SPHOT.
Le mode pilote ne crée pas de base de données distincte : les opérations sur
le compte jetable sont **de vraies écritures Firestore**.

## Protection du périmètre

- Garder `SPHOT_PASSWORD_PILOT_ADMIN_LOGIN=lsm@yopmail.com` dans le fichier
  local non versionné `functions/.env.sphot-ab80b`.
- Choisir **avant le déploiement** un login jetable absent de Firebase :
  `psphottest2026` est la proposition de test. Le prénom `Pilote` et le nom
  `SPHOTTEST2026` devraient générer ce login. Si un suffixe de collision est
  ajouté, arrêter le test ; ne jamais utiliser un compte existant à la place.
- Ajouter dans le même fichier `.env` :

  ```dotenv
  SPHOT_PASSWORD_PILOT_TEST_SAUVETEUR_LOGIN=psphottest2026
  ```

- Conserver les paramètres pilotes déjà actifs (URL, date d'expiration,
  identifiants Sauveteur, Admin et Publicitaire). Aucun mot de passe ou secret
  ne doit être communiqué dans le chat ou stocké sur Git.
- Les quatre nouvelles fonctions refusent tout login différent de celui de
  test. Les opérations Admin demandent aussi une session Firebase valide de
  l'Admin pilote et la correspondance exacte de son territoire.
- Le Flutter compilé en mode pilote interdit aussi la création,
  la modification et la suppression d'un autre sauveteur via le dashboard Web.
- Le Super Admin reste exclu de ces essais.

## Préparation technique à approuver avant déploiement

Depuis le PC et **la branche de test correspondant à ce dossier** :

```powershell
$env:FUNCTIONS_DISCOVERY_TIMEOUT = "60"
firebase deploy --only "functions:upsertSauveteurAccountPilot,functions:sendSauveteurCredentialsEmailPilot,functions:deleteSauveteurAccountPilot,functions:changeSauveteurPasswordPilot,functions:loginSauveteurPilot" --project sphot-ab80b
```

Cette commande déploie seulement des noms pilotes distincts. Elle ne met
pas à jour les fonctions de production `upsertSauveteurAccount`,
`sendSauveteurCredentialsEmail`, `deleteSauveteurAccount` ou
`changeSauveteurPassword`.

Lancer ensuite Flutter sur Chrome en mode pilote depuis la même branche :

```powershell
flutter run -d chrome -t lib/main.dart --dart-define=SPHOT_PASSWORD_PILOT=true --dart-define=SPHOT_PASSWORD_PILOT_TEST_SAUVETEUR_LOGIN=psphottest2026
```

Sans ces deux paramètres Flutter, l'application peut appeler les fonctions
habituelles : ne pas effectuer ce test destructif dans une compilation
normale.

## Scénario manuel en réel, une seule fois

1. Se connecter comme SPHOT Admin pilote (`lsm@yopmail.com`).
2. Créer **Pilote SPHOTTEST2026** dans le territoire de cet Admin, avec une
   adresse email de test contrôlée, une fonction, un poste de secours et
   une période de surveillance déjà prévus pour les essais.
3. Vérifier la génération du login exact `psphottest2026`, du mot de passe
   provisoire et de l'enregistrement dans `territoires/{id}/sauveteurs`
   et `sauveteurAccounts/{login}`. Aucun mot de passe à transmettre.
4. Envoyer les identifiants : un seul mail reçu, état `EMAIL ENVOYÉ`.
5. Se connecter en tant que Sauveteur avec l'accès provisoire,
   changer le mot de passe, puis vérifier la reconnexion avec le nouveau.
6. Revenir comme Admin et affecter **ce compte de test seulement** à un
   deuxième poste puis revenir à un seul poste. Vérifier les deux écritures
   dans `spots/{spotId}/sauveteursAffectes`. Attention : la sauvegarde de
   modification peut régénérer son mot de passe provisoire.
7. Supprimer uniquement **Pilote SPHOTTEST2026** et vérifier le retrait de
   ses affectations et de son compte ; vérifier qu'aucun autre sauveteur
   n'a été supprimé.

## Arrêt et validation

Ne supprimer ni fonctions de production, ni utilisateur non lié au test.
Ne pousser aucun changement dans `main` et ne déployer aucune fonction pilote
sans validation explicite de l'utilisateur après revue du diff et des tests.
Consigner séparément chaque résultat réel (réussi, échoué, non exécuté).
