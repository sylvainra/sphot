# SPHOT ADMIN ↔ Odoo 20 — état de raccordement local

Branche locale : `feature/odoo-admin-raccordement-20261031`.
Base Odoo autorisée pour cet adaptateur : `sphot_publicitaire_checkout_test` seulement.
**Aucune route exposée, aucun paiement lancé, aucune écriture Firestore.**

## Contrats implémentés côté SPHOT

- `odoo_admin_checkout_contract.js` : contrôle du dossier ADMIN déjà approuvé
  (territoire et cohérence SIREN/SIRET), du payeur, des postes, de la grille
  publiée, de la fiscalité et des CGV ; référence et empreinte figées.
- `odoo_admin_checkout_client.js` : recherche idempotente de commande, contrôle
  des 1–4 lignes Odoo, des totaux HT/TVA/TTC et de la facture, méthodes
  atomiques réservées à un addon Odoo ADMIN, preuve Stripe restreinte.
- `odoo_admin_firestore_projection.js` : préparation d'un cycle dédié
  `adminOdooCycles/{reference}` et mise à jour des droits dans
  `subscriptions/{adminUid}`, sans assimiler engagement public et paiement.
- `odoo_admin_test_firestore_sync.js` : synchronisation transactionnelle
  STRICTEMENT sur `sphot-c4-test-20261029` avec opt-in explicite, relecture
  de l'état Odoo, contrôle de la première décision Super Admin par une
  archive serveur `adminOdooReviewEvidence`, puis vérification d'un
  justificatif institutionnel `adminOdooEngagementEvidence` lorsque le
  paiement n'est pas immédiat. Aucune écriture réelle exécutée.
- `functions/index.js` : le scheduler des impayés historiques ignore les
  abonnements marqués `odooAdminManaged: true`. L'expiration annuelle reste
  gérée séparément. L'envoi effectif des relances n'est pas encore branché.

## Addon Odoo ADMIN écrit localement, installation à valider

Le dossier `odoo_addon_patch/sphot_admin_checkout/` est un addon Odoo 20
distinct, développé après lecture de l'archive réelle Windows
`sphot_advertiser_checkout_20261031_154833.zip` (SHA-256 :
`22467e849e44fb3fdc062ca3a8fbfbe1fad48311ed7f5d1536dbed8a0c53fe47`).
Il dépend de `sphot_advertiser_checkout` pour les champs uniques de commande
et de facture et pour le groupe technique. Il ne modifie pas ce dernier.

Modèle ADMIN : `sphot.admin.checkout`, non installé à ce stade.

| Méthode | Corps principal | Contrat de retour |
| --- | --- | --- |
| `create_or_get_draft_order` | `sphot_reference`, `sphot_fingerprint`, `expected_untaxed_cents`, `expected_total_cents`, `order_values` | `sphot_admin_atomic_order_v1` |
| `confirm_and_post_one_invoice` | `sphot_reference`, `sphot_fingerprint`, `sale_order_id`, `expected_total_cents` | `sphot_admin_atomic_invoice_v1` |
| `read_stripe_checkout_evidence` | `sphot_reference`, `sphot_fingerprint`, `invoice_id` | `sphot_admin_stripe_evidence_v1` |

Pour les deux premières méthodes, le retour doit inclure `outcome` (`created`
ou `existing`), `contract`, `reference`, `fingerprint`, `order`, et aussi
`invoice` pour la seconde. Les commandes et factures sont marquées avec
`x_sphot_reference`, `x_sphot_fingerprint` ; la facture est liée à la commande
via `x_sphot_sale_order_id`. L'addon doit gérer concurrence, unicité, droits du
compte technique, taxe/position fiscale et postage de la facture de façon
atomique. Aucun prix issu du navigateur ne doit faire autorité.

L'attestation Stripe doit limiter les transactions à la facture visée, avec
`stripe_providers`, `demo_providers` et `transactions` (montant, devise,
référence, état, fournisseur, facture) ; aucun accès direct aux modèles
`payment.provider` ou `payment.transaction` depuis le compte RPC.

## À faire avant un essai Odoo réel

1. Après validation, copier le **nouvel addon séparé** sur Windows sans
   écraser le module PUBLICITAIRE ; installer dans la seule base Odoo
   neutralisée, après sauvegarde et contrôle des droits.
2. Ajouter l'orchestrateur serveur authentifié : lecture Firestore et preuve
   immuable de la première validation Super Admin, contrôle payeur/CGV/TVA,
   appel Odoo, puis transaction Firestore idempotente.
   L'ébauche TEST de la transaction est codée, mais les deux collections
   de preuves ne sont pas encore alimentées par des contrôleurs serveur
   autorisés ; ne jamais les remplir à partir de simples champs clients.
3. Brancher le portail SPHOT ADMIN aux factures Odoo ; piloter les relances
   J+7/J+15 et la revue humaine J+30 sans suspension automatique.
4. Tester commande, facture, engagement public, Stripe TEST et rapprochement
   bancaire dans la base neutralisée, puis valider avant déploiement.

Les prix actuels quatre tranches restent inchangés. Les collections
historiques ne sont pas supprimées : aucun effacement n'est nécessaire à ce
stade. Aucun push ni déploiement n'a été effectué.
