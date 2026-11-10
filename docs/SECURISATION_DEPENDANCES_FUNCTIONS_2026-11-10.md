# SPHOT — Sécurisation des dépendances Cloud Functions

Date : 10 novembre 2026. Projet Firebase : `sphot-ab80b`.

## Objet

Sécuriser les deux fonctions nécessaires à la traçabilité des versions des
documents juridiques, sans réécrire les autres workflows SPHOT.

## Changements

- Mise à jour compatible du graphe de dépendances (`functions/package-lock.json`).
- `firebase-functions` : `^7.4.0` (auparavant `^7.0.0`).
- `firebase-admin` : `^13.10.0` (auparavant `^13.6.0`).
- `nodemailer` : `^10.5.0` (auparavant `^8.0.11`).
- Retrait de `firebase-functions-test`, inutilisé par les tests du dépôt et
  incompatible avec `firebase-admin` 14.
- Documentation JSDoc requise par ESLint dans
  `functions/legal_document_versions.js`.
- Test sans envoi réel de la génération et du transport d'e-mail SPHOT avec
  Nodemailer 10 (`functions/test/nodemailer_transport_compatibility.test.js`).

## Contrôles effectués

- `npm --prefix functions ci` : installation reproductible.
- `npm --prefix functions run lint` : aucune erreur.
- Chargement de `functions/index.js` : 85 exports, dont les deux fonctions
  juridiques prévues.
- 13/13 tests ciblés : réussis.
- Suite Node globale : 287/290 tests réussis. Les trois échecs concernent
  `functions/test/commercial_radius_catalog.test.js` et le catalogue des
  tarifs commerciaux ; ni ces tests ni leur code métier n'ont été modifiés.
- `npm --prefix functions audit --omit=dev` : **0 critique, 0 élevée,
  8 modérées**.

## Limite de sécurité et compatibilité

Les huit vulnérabilités modérées restantes sont héritées de dépendances
internes de Firebase Admin 13, notamment `uuid`. La montée vers Firebase
Admin 14 les résout dans l'audit, mais l'essai a révélé un changement cassant :
`admin.firestore()` n'est plus exposé, alors que les Cloud Functions SPHOT
l'utilisent largement. Cette migration doit donc faire l'objet d'un chantier
distinct avec adaptation des appels et tests de non-régression.

Les validations locales ont été réalisées sous Node.js 24, tandis que le
runtime Firebase du projet est configuré en Node.js 22. Revalider les tests
sur le PC de développement avant déploiement.

## Périmètre de publication

Seules les fonctions `acceptSauveteurLegalTerms` et
`resubmitAdvertiserCorrection` sont visées par le déploiement ciblé. Les
documents déjà publiés dans Firestore ne sont pas modifiés par ce paquet.

**Statut :** correctif préparé et vérifié localement. Aucun déploiement ni
commit/push Git effectué à ce stade.
