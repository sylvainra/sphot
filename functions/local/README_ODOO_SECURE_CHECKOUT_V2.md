# SPHOT Publicitaire — raccordement local au module Odoo anti-doublons

État de travail du 28/10/2026. **Aucun déploiement ni paiement effectué.**

## Périmètre

- Code conservé sur la branche `feature/odoo-publicitaire-simulation-20261024`.
- Module Odoo 20 Community installé sur Windows : `sphot_advertiser_checkout`.
- Seule base autorisée pour le nouveau parcours :
  `sphot_publicitaire_checkout_test` (base **neutralisée**).
- Compte API technique existant, client fictif Odoo ID `8`, produit de service ID `1`.
- Tarification : uniquement `FR_ADVERTISER_RADIUS` (108 tarifs). L'ancien
  catalogue `FR_ADVERTISER` à 90 prix est rejeté ; aucun prix n'est inventé
  par le navigateur ou la passerelle locale.
- Les commandes/factures déjà obtenues (S00006 / FAC/2026/00006) ne sont
  **ni recréées ni modifiées** par la préparation de ce code.

## Contrat vérifié dans `models/checkout.py` communiqué le 28/10/2026

`sphot.advertiser.checkout/create_or_get_draft_order` attend :

- `sphot_reference`, au format `SPHOT-PUB-PROD-` + 16 caractères hexadécimaux ;
- `sphot_fingerprint`, SHA-256 hexadécimal de
  `référence|partner_id|product_id|prix_unitaire_HT_2_decimales|remise` ;
- `expected_untaxed_cents` ;
- `order_values`, avec exactement `partner_id`, `client_order_ref`,
  `origin` et `order_line`.

`sphot.advertiser.checkout/confirm_and_post_one_invoice` attend :

- `sphot_reference`, `sphot_fingerprint`, `sale_order_id`,
  `expected_total_cents` (TTC lu dans la commande Odoo).

Réponses : contrats `sphot_advertiser_atomic_order_v1` et
`sphot_advertiser_atomic_invoice_v1`, avec résultat `created` ou `existing`.
Le code côté SPHOT vérifie les références, identifiants, montants, devise,
états et rattachement facture/commande. Lorsqu'une facture existe déjà,
notamment payée, SPHOT relit l'état Odoo et **ne rappelle pas** les méthodes
d'écriture qui refuseraient normalement ce rejeu.

## Isolation du test

Le nouveau mode du serveur local est opt-in : variable du **processus Node**
`SPHOT_ODOO_SECURE_CHECKOUT_TEST=true`. Il réutilise la clé API Odoo fournie
de façon privée au processus local, sans l'afficher ni la stocker. Il bloque
les anciennes actions d'écriture et impose la base neutralisée.

Les actions serveur autorisées sous `/order`, après vérification de l'identité
Firebase et du devis commercial côté serveur, sont :

- `secure_status` : lecture de la commande et de la facture ;
- `secure_draft` : création/récupération idempotente du devis Odoo ;
- `secure_invoice` : confirmation et facture unique ;
- `secure_stripe_status` : contrôle de transaction Stripe Odoo en mode TEST ;
- `secure_stripe_checkout` : préparation du lien de portail Odoo local, sans
  autorisation de paiement ni activation publicitaire par SPHOT.

Le service Flutter `OdooLocalOrderService` expose désormais ces actions derrière
le drapeau de compilation `SPHOT_ODOO_SECURE_CHECKOUT=true`. Dans ce mode :

- `DEVIS & COMMANDE` propose la création/récupération du devis brouillon,
  après confirmation explicite ;
- `PAIEMENT CB` propose la facture unique, puis le portail Stripe Sandbox ;
- `DOCUMENTS & FACTURES` relit les références et statuts sans écriture ;
- les anciens boutons Odoo/Démo ne sont pas affichés. Sans les deux drapeaux
  de test (Node et Flutter), le parcours historique reste inchangé.

Le mode reste **désactivé par défaut**. Ne pas l'activer sur un environnement
public : seul le serveur de développement local `127.0.0.1:8767` est prévu.
L'essai contre l'instance Windows et le contrôle des droits de lecture du
compte technique restent à faire, après vérification du parcours Flutter.

Le résultat `paymentConfirmed` ne peut être vrai que si la transaction Odoo
Stripe TEST est `done`, la facture est `paid`, son solde est nul et un
règlement lui est lié. Même dans ce cas, aucune campagne n'est activée et
aucune écriture Firestore n'est effectuée par ce serveur local.

## Vérifications effectuées dans la copie Git locale

- Tests ciblés de la nouvelle passerelle, de son contrat et de l'ancienne
  passerelle : réussis sur des mocks, sans appel au serveur Odoo réel.
- ESLint : réussi.
- Suite complète : 39 fichiers de tests réussis sur 40. Le fichier historique
  `commercial_radius_catalog.test.js` présente trois assertions tarifaires
  incompatibles avec le code de référence existant ; **aucun fichier tarifaire
  n'a été modifié** dans cette adaptation.

Prochaine étape : tester sur Windows l'ouverture du parcours Flutter local
et vérifier en lecture les droits du compte technique sur la base neutralisée,
puis réaliser un essai de bout en bout **après validation explicite**.
Aucune seconde validation Super Admin n'est prévue après un paiement confirmé.
