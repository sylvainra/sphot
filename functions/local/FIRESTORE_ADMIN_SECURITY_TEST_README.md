# SPHOT — sécurité Firestore : brouillon TEST (31/10/2026)

## Découverte confirmée

Les règles **actuellement communiquées** pour `sphot-ab80b` accordent
`allow read, write: if true` aux collections `adminRequests`, `admins`,
`subscriptions`, `territoires` et plusieurs autres. Le filtrage Super Admin
et la facturation Odoo ne suffisent donc pas à protéger l'accès au portail.
Les collections Odoo dédiées, non mentionnées dans ces règles, sont par défaut
inaccessibles aux clients (mais accessibles au SDK Admin côté serveur).

## Ce que contient ce paquet

| Fichier | Utilisation |
| --- | --- |
| `functions/local/firestore_security_admin_TEST.rules` | Proposition **stricte pour émulateur uniquement** |
| `firebase.admin-security.TEST.json` | Configuration alternative, non référencée par `firebase.json` |
| `functions/test/firestore_security_admin_draft.test.js` | Vérifications statiques, pas un interpréteur de règles |
| `functions/test/firestore_security_admin_emulator.js` | Quelques vérifications anonymes réelles via REST sur l'émulateur |

### Ce que le brouillon protège

- Approbation `adminRequests.status=approved` impossible par un client :
  réservée au SDK serveur `approveAdminInitialRequest`.
- Preuves `adminOdooReviewEvidence`, `adminOdooEngagementEvidence` et
  `adminOdooCycles` inaccessibles au client.
- Pas de passage direct de `subscriptions.status` à `trial`/`active`.
- Lecture des dossiers ADMIN limitée au Super Admin authentifié ou au
  demandeur associé par `proConnect.uid`.
- Édition de coordonnées de facturation par le demandeur (sous réserve que
  l'identité Firebase corresponde au `proConnect.uid` conservé dans la demande).
- Super Admin : seul un rejet ou retour en attente côté client est prévu.
- `publicSpots` : lecture publique, aucune écriture client.
- Absence de règles globales permissives.

## Incompatibilités connues : NE PAS DÉPLOYER

Les flux suivants sont encore directs depuis Flutter et seraient bloqués par
ce brouillon. Ils doivent être migrés ou sécurisés individuellement **avant
toute publication** :

1. `super_admin_admin_workflow_panel.dart` : démarrage de l'essai de 8 jours
   et modifications commerciales dans `subscriptions`/`admins`.
2. `super_admin_subscriptions_page.dart` et certains panneaux Super Admin :
   changement de statut d'abonnement manuel ; l'activation commerciale
   doit dépendre de la preuve contractuelle ou du paiement Odoo rapproché.
3. `admin_subscription_panel.dart` : sélection des postes, nombre et montant
   calculés côté Flutter ; ces montants et cette sélection ne doivent pas
   devenir une source fiable sans validation serveur.
4. `admin_dashboard_page.dart` : certaines requêtes lisent *toutes* les
   `adminRequests`/`subscriptions`, ce qui n'est pas acceptable pour un
   compte Admin ordinaire ; remplacer par des requêtes ciblées.
5. Inscription / correction ProConnect : vérifier sur émulateur que
   `proConnect.uid` correspond bien à l'UID Auth de la session. L'ID du
   document `adminRequests` est généré séparément. La correction actuelle
   écrit aussi des champs de suivi administratifs réservés au serveur ;
   elle sera refusée tant que ce flux n'a pas été séparé.
6. `territoires` et ses sous-collections, sauveteurs, carte, publicités,
   annonceurs, `settings`, `communes`, `test` : classification de chaque
   accès manquante. Le brouillon les ferme par défaut ; le portail complet
   ne fonctionnera donc pas avec ces règles en l'état.
7. `legalDocuments`/`legalVersions` : la lecture reste publique dans ce
   brouillon. Il faut vérifier que ces collections ne contiennent pas de
   brouillons internes ou de données confidentielles avant publication.

## Exécution locale sans aucun projet Firebase réel

Dans VS Code, à la racine du dépôt :

```powershell
node --test functions/test/firestore_security_admin_draft.test.js
```

Pour faire évaluer les règles **réellement** par Firebase Emulator, la CLI
Firebase et Java doivent être installés :

```powershell
firebase emulators:exec --project demo-sphot-admin-security --config firebase.admin-security.TEST.json --only firestore "node functions/test/firestore_security_admin_emulator.js"
```

La cible `demo-sphot-admin-security` est un projet fictif sans ressource
distante. Le script refusera tout autre port ou hôte que `127.0.0.1:8181`
ou `localhost:8181`. Ne pas ajouter `--project sphot-ab80b`.

Les tests REST couvrent les accès **anonymes seulement** : il reste à tester
avec Firebase Emulator des identités simulées (demandeur, Admin, Super Admin,
Super Admin expiré), les créations et les corrections, ainsi que les flux
SPHOT PUBLICITAIRE et sauveteurs avant de proposer le moindre déploiement.

## Décision de déploiement

**NON VALIDÉE.** Aucun changement aux règles publiées, ni au fichier
`firebase.json` du projet SPHOT. Préserver le dépôt existant et la branche
de travail de l'utilisateur ; installer ces fichiers nouveaux uniquement.
