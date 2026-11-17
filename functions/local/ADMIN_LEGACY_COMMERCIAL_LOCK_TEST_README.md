# SPHOT ADMIN — verrouillage des anciens chemins commerciaux (TEST)

Ce lot verrouille seulement les anciens chemins de modification commerciale.
Il **ne déclenche aucun déploiement Firebase**, ne modifie pas la base Odoo,
et n'active aucun abonnement en production.

## Changements

- L'ancien déclencheur `orders/{orderId}` conserve son export, mais ne
  peut plus activer l'abonnement ni les droits de diffusion. Une approbation
  Firestore seule ne prouve ni engagement public ni paiement Stripe/Odoo.
- Les boutons historiques de changement manuel de statut de l'abonnement
  affichent une explication et n'écrivent plus dans Firestore. Un paiement
  n'est jamais déduit d'un clic « PASSER ACTIF ».
- Le bouton d'approbation d'ancienne commande est conservé comme information,
  mais sans écriture ni activation.
- Le renouvellement d'essai de huit jours attend une **nouvelle fonction
  serveur Super Admin dédiée**. L'ancien code de transaction Flutter est
  retiré du widget ; son historique reste dans Git. L'autorisation initiale
  des huit jours déjà installée n'est pas modifiée.
- L'Admin peut consulter les devis et choisir les postes à l'écran, mais
  l'enregistrement direct de l'offre tarifée est bloqué tant que le serveur
  n'a pas figé et vérifié le devis Odoo.
- Le planificateur ne marque pas « overdue » les abonnements portant
  `odooAdminManaged: true` simplement parce que `nextInvoiceDate` est dépassé.
  J+7/J+15/J+30 reste un processus distinct, sans suspension automatique.

## Sécurité et limites

- Les règles Firestore historiques largement ouvertes **ne sont pas
  sécurisées par ce patch** : les règles strictes TEST doivent encore être
  adaptées aux lectures/écritures restantes, puis déployées séparément.
- Les droits commercialement activés doivent venir d'une projection serveur
  vérifiant l'approbation initiale Super Admin (localité/SIREN/SIRET), le
  territoire, l'engagement contractuel ou le rapprochement Stripe + Odoo.
- Aucun endpoint commercial Odoo de production n'est déployé dans ce lot.
- Les fonctions déjà déployées continueront leur comportement antérieur
  jusqu'à une **mise à jour explicitement autorisée et vérifiée**.
- Le reste du parcours SPHOT PUBLICITAIRE C1–C4 n'est pas modifié.

## Contrôles locaux

```powershell
node --test functions/test/admin_legacy_commercial_lock.test.js functions/test/admin_trial_authorization.test.js functions/test/admin_initial_approval.test.js
flutter analyze --no-pub lib/web/super_admin/widgets/super_admin_admin_workflow_panel.dart lib/web/super_admin/pages/super_admin_subscriptions_page.dart lib/web/admin/pages/admin_subscription_panel.dart
```

## Prochain raccordement

1. Relier le devis contractuel multi-tranches au flux de facturation Odoo
   (commande, facture, statut de paiement) sans créer de paiement fictif.
2. Exposer le contrôle serveur des pièces d'engagement pour les collectivités.
3. Implémenter et tester la prolongation d'essai côté serveur avec trace Super Admin.
4. Finaliser les règles Firestore, la recette intégrée TEST, puis valider
   explicitement chaque déploiement avant toute production.
