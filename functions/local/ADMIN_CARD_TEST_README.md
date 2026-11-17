# SPHOT ADMIN — cycle carte Stripe TEST distinct (2026)

Scénario entièrement fictif dans Firestore `sphot-c4-test-20261029` et Odoo
`sphot_publicitaire_checkout_test`. Il n'utilise **aucun** des deux postes
LONGE 09/LONGE 13 et n'intervient jamais dans le projet Firebase historique.

- Référence déterministe : `SPHOT-ADM-TEST-68D69D07E8DDE668`.
- 2 postes purement fictifs : 898,00 € HT, 1 077,60 € TTC (TVA de simulation).
- SIREN/SIRET sentinelles de test, sans valeur administrative.
- Client Odoo fictif déjà validé ID 8 ; produits de tranche ID 2–5.
- Aucune preuve d'engagement public sur ce cycle **carte**.
- Le code ne crée **aucun** paiement Stripe et ne force jamais une facture à
  « payée » ; la transaction doit être réellement confirmée par Stripe TEST
  dans Odoo et rapprochée avant les droits Firestore TEST.

## Étapes sécurisées

Tous les appels utilisent `node functions/local/odoo_admin_card_test_cycle.js MODE`.

1. `preflight` : lecture seule Firestore TEST, aucune écriture (étape initiale).
2. `seed` : création atomique des 8 documents de la nouvelle fixture TEST,
   uniquement si `SPHOT_ADMIN_TEST_FIRESTORE_WRITES=true`,
   `SPHOT_ADMIN_TEST_PROJECT_ID=sphot-c4-test-20261029`,
   `GCLOUD_PROJECT=sphot-c4-test-20261029`,
   `GOOGLE_CLOUD_PROJECT=sphot-c4-test-20261029` et
   `SPHOT_ADMIN_TEST_CARD_SEED=true`. Reprise idempotente.
3. `invoice` : création/relecture idempotente d'une commande et d'une facture
   Odoo TEST uniquement si `SPHOT_ADMIN_TEST_ODOO_WRITES=true`,
   `SPHOT_ADMIN_TEST_ODOO_DATABASE=sphot_publicitaire_checkout_test` et
   `SPHOT_ADMIN_TEST_CARD_INVOICE=true`. Aucune écriture Firestore.
4. `stripe` : lecture des preuves du fournisseur Stripe TEST, du fournisseur
   Démo et des transactions liées à **cette nouvelle facture**. Le fournisseur
   Démo publié est bloquant ; aucune transaction existante ne doit être
   ignorée. Aucun paiement déclenché par le script.
5. Paiement manuel sur le portail de **cette facture Odoo TEST uniquement**
   via Stripe en mode TEST avec identifiants de test. Pour recevoir ses
   notifications, l'Odoo installé sur `127.0.0.1` peut nécessiter un dispositif
   de transfert de webhook local. Ne pas exposer Odoo publiquement ni entrer
   des clés réelles sans décision explicite.
6. Refaire `preflight` : le statut `in_payment` ou `partial` n'ouvre aucun
   droit. Seul `paid` **rapproché** et une unique transaction Stripe `done`
   autorisent l'étape suivante.
7. `activate` : vérifie à nouveau la facture et le paiement puis projette
   les droits exclusivement sur Firestore TEST, sous l'opt-in d'écriture
   Firestore ci-dessus et `SPHOT_ADMIN_TEST_CARD_ACTIVATE=true`.

Le dossier public déjà activé par engagement simulé, la base Odoo hors TEST,
les données PUBLICITAIRE et les données de production restent inchangés.
Ne jamais recopier ces justificatifs fictifs dans un dossier réel.
