# SPHOT ADMIN — deuxième série de tests Firestore

La première série a déjà testé 21 opérations anonymes avec succès. Celle-ci
teste les droits associés à **trois identités simulées** : demandeur ProConnect,
utilisateur tiers et Super Admin (valide ou expiré).

Ce répertoire comporte son **propre** `package.json`, indépendant du projet
Flutter et des Cloud Functions SPHOT. Il ne modifie aucun autre package.

Prérequis : Node.js, `npm`, Firebase CLI et Java disponibles sur Windows.

Dans le terminal VS Code à la racine du dépôt SPHOT :

```powershell
npm install --prefix functions/local/admin_security_authenticated_tests --ignore-scripts --no-audit --no-fund
firebase emulators:exec --project demo-sphot-admin-security --config firebase.admin-security.TEST.json --only firestore "node functions/local/admin_security_authenticated_tests/test.mjs"
```

**Ne pas modifier `--project`** : l'identifiant `demo-` ne possède aucune
ressource Firebase réelle. Le script vérifie que le seul émulateur utilisable
est celui de Firestore sur `localhost:8181`.

Vérifications visées :

- Un demandeur lit son dossier, son compte et son abonnement ; pas ceux d'un
  autre demandeur ni toute la liste des dossiers.
- Le Super Admin peut consulter les dossiers uniquement pendant une session
  authentifiée encore valide.
- Ni le demandeur ni le Super Admin ne peuvent directement approuver une
  demande ou activer un abonnement ; ces décisions sont côté serveur.
- Une preuve Super Admin n'est pas inscriptible depuis Flutter.
- Un demandeur peut mettre à jour son contact de facturation mais ne peut
  pas attribuer des droits commerciaux à son abonnement.
- Une nouvelle inscription conforme reste possible, ainsi qu'un rejet
  Super Admin et une correction limitée.

Ces tests sont **un complément**, pas un feu vert pour déployer les règles :
les parcours historiques SPHOT, les sauveteurs, l'offre ADMIN, la publicité
et les documents juridiques doivent ensuite être vérifiés individuellement.
