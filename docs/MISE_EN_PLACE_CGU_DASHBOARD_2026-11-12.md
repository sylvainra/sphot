# SPHOT — Livraison ciblée des documents juridiques dans le dashboard

Ce lot est volontairement limité à l'édition et à l'enregistrement sécurisé **depuis le dashboard Super Admin**.

- CGU Grand Public : identifiant `cgu`, document déjà publié, inchangé.
- CGU ADMIN `adminCgu` : 14 articles approuvés.
- CGU PUBLICITAIRE `advertiserCgu` : 12 articles approuvés.
- CGU SAUVETEUR `sauveteurCgu` : 8 articles approuvés.
- Charte SAUVETEUR `sauveteurCharter` : 7 rubriques approuvées.

Le bouton **ENREGISTRER DANS FIREBASE (BROUILLON)** fait une écriture contrôlée dans `legalEditorialDrafts/{documentId}` et une relecture indépendante. Une confirmation distincte est indispensable pour **VALIDER**, puis **PUBLIER ET ARCHIVER** vers `legalDocuments/{documentId}`, `chapters` et l'historique `legalVersions`.

Codebase Firebase `legal` distincte de `default`. **Ne pas déployer les fonctions métier par ce lot.** Ne pas activer les CGU professionnelles dans les parcours de connexion avant publication des documents et synchronisation des clients.

Cette livraison n'effectue aucun déploiement automatique ni écriture Firebase de production. Déployer seulement le module juridique et le dashboard après validation de l'environnement et tests.
