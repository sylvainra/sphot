# SPHOT ADMIN — verrouillage commercial V2 (TEST local uniquement)

Le patch V1 ne s'appliquait pas au widget Super Admin du poste Windows,
car l'indentation et les retours à la ligne diffèrent de la copie de travail.
Le patch initial n'a **pas** été appliqué : Git s'est arrêté sans modifier
les cinq fichiers, conformément au contrôle préalable.

Cette V2 est cumulative mais ne réapplique **pas** le patch V1.

## Composition

- `sphot_admin_legacy_commercial_lock_V2_TEST.patch` : quatre modifications
  de code strictement identiques à la V1, sans le widget en conflit.
- `functions/local/admin_legacy_lock_v2.js` : contrôle puis réécriture bornée
  de deux méthodes du widget existant, indépendamment des espaces/indentations.
- `functions/test/admin_legacy_lock_v2.test.js` : tests de transformation
  avec mises en forme variantes et rejet des éditions inattendues.

## Procédure sûre

1. Contrôler le widget : `node functions/local/admin_legacy_lock_v2.js --check`.
2. Vérifier le patch Git : `git apply --check sphot_admin_legacy_commercial_lock_V2_TEST.patch`.
3. Appliquer le patch sur les quatre fichiers (pas de `--force`).
4. Exécuter `node functions/local/admin_legacy_lock_v2.js --apply`.
   La réécriture crée une **sauvegarde datée à côté du widget** avec suffixe
   `.before_admin_lock_v2_...bak`, sans écraser l'ancien fichier de sauvegarde.
5. Exécuter les tests existants et nouveaux, puis `flutter analyze`.

L'algorithme refuse l'opération si les méthodes à neutraliser ne comportent
pas les preuves attendues des anciennes écritures (transaction de renouvellement
et `order.reference.set`), si les bornes sont ambiguës, ou si le verrou existe.
Il conserve sans modification la validation initiale d'essai déjà raccordée au
serveur et les autres méthodes de la page.

**Aucune opération Odoo, aucun déploiement Firebase, aucune modification des
règles de sécurité Firestore de production.** Les anciennes règles ouvertes
doivent toujours être corrigées avant toute production.

Le chantier prioritaire reste le raccordement de l'abonnement SPHOT ADMIN à
la commande, à la facturation et aux justificatifs vérifiés dans Odoo.
