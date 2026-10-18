# SPHOT — Odoo, grille des six rayons et remises client

## Décisions et périmètre

- SPHOT Publicitaire : **6 rayons mondiaux** (5, 15, 50, 150, 300, 500 km), **3 offres** (Carte, Fiches, Pack) et **6 durées** (1 semaine, 2 semaines, 1 mois, 2 mois, 6 mois, 1 an).
- Source des prix : catalogue versionné `commercialPricingMarkets/FR_ADVERTISER_RADIUS`, **108 cellules**. Publication par le Super Admin seulement après saisie complète des 108 prix. Aucun prix fictif introduit.
- L'ancienne grille de 90 montants dans `FR_ADVERTISER` et toutes ses versions sont conservées **sans modification et sans transposition arbitraire**.
- Tarifs de base SPHOT exprimés HT en EUR à l'international. Odoo doit calculer taxes et TTC selon l'établissement vendeur, l'acheteur, le pays de facturation et la fiscalité applicable.
- Remise individuelle simple, sans code public : le Super Admin attribue **0 à 90 %**, par UID Firebase, séparément pour `ADMIN` et `ADVERTISER_RADIUS`. 0 % retire l'avantage. Le catalogue publié et l'historique ne sont jamais modifiés par une remise.
- Paiement : **Odoo = devis, commandes, factures, avoirs, comptabilité** ; paiement CB via **Stripe paramétré comme fournisseur de paiement Odoo**, sans reconduction automatique. La référence SPHOT est conservée sur les documents Odoo, mais la numérotation fiscale relève uniquement d'Odoo.

## Code créé dans la branche de migration, sans déploiement

1. `functions/commercial_pricing.js` : nouveau marché `ADVERTISER_RADIUS` isolé. Les validations contrôlent 108 cellules.
2. `functions/commercial_quote_pricing.js` : devis indicatif du catalogue publié avec sa version ; optional Firebase ID token, remise client lue uniquement depuis Firestore par le serveur.
3. `functions/commercial_discounts.js` : remises nominatives dans `commercialCustomerDiscounts/{market}__{uid}` et calcul précis en centimes. Aucune modification directe accessible au client.
4. `lib/web/super_admin/widgets/super_admin_advertiser_radius_pricing_table.dart` : saisie et publication du catalogue 108 prix.
5. `lib/web/super_admin/widgets/super_admin_customer_discounts_dialog.dart` : consultation et modification des remises depuis les grilles du Super Admin. Le marché et l'UID client doivent être choisis.
6. `lib/services/published_commercial_quote_service.dart`, étapes 4–5 Publicitaire et écran de tarif Admin : affichage du prix publié, de la remise éventuelle et du net HT. L'ancienne TVA à 20 % figée dans le devis Publicitaire est retirée.
7. `functions/odoo_commercial_bridge.js` : **préparation de la structure de devis**, côté serveur seulement, avec la référence tarifaire et le pourcentage de remise ; aucune connexion API, aucune commande créée.
8. Étape **PAIEMENT CB** insérée entre DEVIS & COMMANDE et DOCUMENTS & FACTURES, avec statut explicitement non activé.

## Avant de pouvoir activer Odoo et le paiement CB

1. Obtenir l'URL HTTPS de l'instance Odoo, sa version, son édition/hébergement et la disponibilité de l'API externe. Pour Odoo 19 Online, la documentation JSON-2 réserve l'API externe à l'abonnement Custom ; ne pas supposer que toutes les offres disposent de la même API.
2. Configurer un utilisateur de service Odoo à privilèges minimaux et une clé API côté **Secret Manager / Cloud Functions**, jamais dans Flutter ou Firestore public.
3. Configurer les articles Odoo du Publicitaire et des quatre tranches de postes SPHOT Admin. Lier les identifiants produits Odoo à une configuration serveur protégée.
4. Résoudre un partenaire Odoo unique par organisation cliente ; conserver `sphotUid` / `requestId` en correspondance. Vérifier le pays, le numéro fiscal s'il existe, la position fiscale et les langues.
5. Configurer devises et règles fiscales Odoo. Tester les situations professionnelles nationales, intracommunautaires et hors UE ; ne pas forcer 20 % de TVA SPHOT partout.
6. Activer le fournisseur Stripe **en mode test dans Odoo** et définir les pays/modes de carte réellement acceptés. Faire émettre par Odoo un lien de paiement pour **la commande chiffrée confirmée**, jamais depuis un montant du navigateur.
7. Vérifier serveur à serveur le statut du paiement, sa référence à la commande Odoo et la facture avant de passer la campagne SPHOT au statut actif. Pas d'activation sur simple retour navigateur.
8. Mettre en place une clé d'idempotence par demande/commande pour éviter commandes, factures et paiements doublés.
9. Tester remises 0 %, 5 %, 10 %, modification Super Admin, calcul centimes, quote→devis→paiement test→facture→avoir et absence de reconduction automatique.
10. Obtenir validation métier et technique avant déploiement des fonctions ou de l'hébergement, puis mettre à jour la référence Git des tests validés.

## Sécurité et non-régression

- **Aucune commande ni paiement Odoo réel n'est déclenché par le code présent.**
- Aucun secret Odoo/Stripe n'est encore configuré dans cette branche.
- La remise ne peut pas être fournie dans le corps de la requête client : seule l'identité Firebase vérifiée la rattache au devis.
- Toutes les anciennes références tarifaires, commandes et factures doivent rester immuables.
- La suppression de collections Firebase historiques n'entre pas dans ce chantier.
- `main` et la production restent inchangés jusqu'à validation finale.
- **Bloquant avant tout déploiement** : auditer les règles Firestore actuellement publiées. Le dépôt ne contient pas de fichier de règles Firestore configuré dans `firebase.json`; ne pas supposer que `commercialCustomerDiscounts` est automatiquement privé. Refuser aux clients toute lecture et écriture directe de cette collection, tout en laissant les écritures serveur Admin SDK autorisées.
- Ne jamais exposer un UID client, une remise individuelle ou une clé Odoo dans une projection publique.
