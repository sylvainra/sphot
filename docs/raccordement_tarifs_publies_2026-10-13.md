# SPHOT — Raccordement des tarifs publiés (état de travail)

> **Note du 28/10/2026 : document historique.** L'ancien catalogue
> `FR_ADVERTISER` à 90 tarifs est retiré des nouvelles ventes. La seule grille
> Publicitaire active est `FR_ADVERTISER_RADIUS` à 108 tarifs, publiée et
> versionnée par le Super Admin. Les anciennes références restent uniquement
> dans l'historique documentaire, sans servir au calcul ni à la facturation.

## Architecture et règle de sécurité

Les catalogues Firestore commercialPricingMarkets/FR_ADMIN et FR_ADVERTISER sont la seule référence **des prix publiés**. Les brouillons, programmations et archives ne servent jamais à calculer une nouvelle commande.

- ADMIN : tarifs marginaux annuels 499 / 399 / 299 / 199 EUR HT par poste (1er, 2–4, 5–9, 10+).
- ANNONCEUR : 90 cases France (territoire administratif x offre x durée), sans rayon ni exclusivité.
- Une commande doit enregistrer côté serveur un **instantané immuable** des montants, de la version de grille et de sa date, et ne doit jamais être modifiée par une révision tarifaire future.
- Les commandes, factures et abonnements historiques ne sont pas recalculés.

## Phase 1 — Aperçu en lecture seule, sur branche de test

- La nouvelle Cloud Function previewPublishedCommercialQuote lit uniquement la grille publiée et retourne montant HT, référence de version, détails de calcul et previewOnly=true.
- Elle refuse une grille publiée manquante ou invalide plutôt que de revenir à un ancien tarif.
- Le client Flutter commun est lib/services/published_commercial_quote_service.dart.
- Le portail ADMIN, section PAIEMENT (toujours en mode test), affiche un aperçu dégressif du nombre de postes enregistré dans subscriptions/{adminUid}.
- Aucun devis contractuel, commande, abonnement, paiement ou facture n'est créé ou modifié par ce mécanisme.
- Tester les deux calculateurs via node --test functions/test/commercial_quote_pricing.test.js et Flutter via flutter test test/published_commercial_quote_service_test.dart.

## Phase 2 — À développer après validation de la phase 1

1. Migrer le calcul et l'enregistrement de l'offre ADMIN dans admin_subscription_panel.dart (actuellement un prix unique hérité).
2. Migrer la confirmation de commande dans admin_subscription_order_service.dart **et la validation serveur** : recalcul du prix publié, figement des tranches, nombre de postes, devise, HT/TVA/TTC, version et conditions.
3. Adapter admin_workflow.js, les courriels et documents de devis, les statistiques financières et les renouvellements à la tarification marginale, sans remplacer les commandes historiques.
4. Refonte du parcours ANNONCEUR : le système historique AdvertisingPricingConfig reste fondé sur des rayons et ne doit pas être utilisé pour de nouvelles commandes avec le catalogue à 90 prix.
5. Séparer l'activation financière et les paiements (notamment Stripe Checkout) de l'aperçu tarifaire, avec vérification serveur obligatoire avant toute activation.

Déploiement autorisable pour la phase 1 seulement : functions:previewPublishedCommercialQuote, après contrôle ESLint et Flutter et accord explicite. Ne pas fusionner dans main avant validation.
