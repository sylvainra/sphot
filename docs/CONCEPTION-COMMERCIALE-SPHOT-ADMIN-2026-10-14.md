# SPHOT ADMIN — Conception commerciale unifiée
_Date de conception : 14/10/2026. Statut : architecture métier et orientations VALIDÉES ; maquettage fonctionnel détaillé À VALIDER avant changement de code._

## 0. Référence de reprise obligatoire
- Dépôt : `Sylvainra/SPHOT` ; branche de travail : `codex/advertiser-pricing-table-v1`.
- Ce fichier **ne déploie ni ne modifie aucune fonction applicative**. Avant chaque intervention : vérifier HEAD, changements locaux, schéma Firestore et règles de sécurité. Ne pas reprendre les versions héritées de `main`.
- Lire aussi : `docs/SUIVI-SPHOT-ADMIN-PAIEMENT-2026-10-13.md` et `docs/raccordement_tarifs_publies_2026-10-13.md`.

## 1. Décisions validées par le demandeur (ne pas reposer)
1. Seulement **deux rubriques** côté Admin : **ABONNEMENT** et **FACTURES & PAIEMENTS**. Les fonctions utiles de PAIEMENT et DOCUMENTS & FACTURES sont migrées dans ces deux ensembles après approbation des écrans, sans disparition des historiques.
2. **Année civile** : début à l'activation, échéance 31 décembre, période suivante à partir du 1er janvier.
3. **Aucun prorata**, même pour première activation en cours d'année. Le plein tarif annuel est dû selon les conditions contractuelles acceptées.
4. Grille **progressive marginale par poste** publiée par Super Admin (prix publiés au 13/10/2026 : 1er 499 € HT, 2–4e 399 €, 5–9e 299 €, 10e+ 199 €). Ne jamais réintroduire un prix fixe, un calcul local distinct ni une grille brouillon.
5. **8 jours d'essai distincts** de l'abonnement. Présence des SPHOTS sur carte indépendamment de l'abonnement ; accès temps réel conditionné à essai autorisé ou abonnement valide, sous responsabilité de l'Admin pour les informations de baignade.
6. **Aucune validation financière quotidienne par le Super Admin**. Réconciliation, relances, facturation, paiements, renouvellements automatisés autant que réglementairement/techniquement possible ; supervision des anomalies seulement.
7. **Carte bancaire** : activer automatiquement uniquement après confirmation serveur du prestataire (webhook authentifié, idempotent), pas sur clic ou retour navigateur. **Commande publique** : permettre une activation avant encaissement si l'engagement contractuel est véritablement vérifié et les autres conditions remplies ; une référence saisie n'est pas une preuve suffisante.
8. Une **chronologie commerciale commune** des devis, commandes, factures, avoirs et paiements, sans confusion entre leurs statuts.
9. CGV versionnées par le Super Admin, accessibles et **acceptées explicitement avant confirmation de la commande**, preuve horodatée liée à l'identité et à la version signée. Sans version valide publiée ni acceptation vérifiable : aucune commande ferme.
10. **Facturation électronique France** : prévoir le circuit adapté au public (Chorus Pro / plateforme agréée selon cas) et aux entreprises (plateforme agréée / e-reporting). Architecture internationale : pays, devise, identification fiscale, langue, catégories fiscales, canal réglementaire. Ne pas créer de facture « conforme » sans prestataire/circuit légal opérationnel.

## 2. Maquette fonctionnelle proposée — ABONNEMENT (À VALIDER)
Écran unique, panneau droit avec gabarit de 430 px et Fire SVG rouge à la taille des panneaux existants. Quatre sections repliables, sans répétition de tableaux.
- **01. POSTES ET OFFRE** : cases sélection des postes avec `idSphot — nom`, tri stable ; grille publiée et référence visible ; lignes par tranche (quantité x prix unitaire, montant à droite), total annuel HT rouge ; début à l'activation, fin 31/12 ; sans prorata clairement explicité ; aucune simulation ne constitue un devis contractuel.
- **02. ORGANISME PAYEUR** : organisation, numéro d'établissement ou identifiant local, identité et autorité du signataire, pays, adresse, contact, email de facturation, TVA/identifiants applicables. Montrer uniquement les champs pertinents selon type d'organisme et pays.
- **03. MODALITÉS DE RÈGLEMENT** : CB sécurisée ou circuit commande publique (si éligible). Selon mode, recueillir le consentement aux débits récurrents et notifications OU les références d'engagement, service/code Chorus si nécessaire, pièces/validation contractuelle vérifiables. Conditions d'échéance affichées.
- **04. CONDITIONS ET CONFIRMATION** : récapitulatif figé (postes, année, grille, HT, traitement fiscal, TTC ou libellé fiscal légal, mode, renouvellement), consultation CGV publiées (version + date), acceptation explicite non précochée, bouton **CONFIRMER MA COMMANDE** disponible seulement quand toutes les étapes sont éligibles.
- Afficher états lisibles « brouillon », « en attente de paiement », « en attente d'engagement », « abonnement actif » sans afficher un statut non réel. Prévoir messages d'erreur permettant de régulariser sans intervention du Super Admin.
- L'activation technique doit être **pilotée côté serveur**, après condition commerciale vérifiée, et ne jamais être déclenchée par une écriture Firestore client en `status: active`.

## 3. Maquette fonctionnelle proposée — FACTURES & PAIEMENTS (À VALIDER)
Même panneau, sans recalcul indépendant du prix.
- En-tête : statut contractuel, montant des **factures réellement échues ou à régler**, prochaine échéance si connue (pas de données fictives).
- **Chronologie unique datée** et filtrable : devis émis, commandes confirmées, factures, avoirs, émission/transmission/réception de facturation électronique, paiements/règlements et remboursements.
- Chaque ligne : nature, référence, date, montant, devise, statut, lien vers fichier officiel et preuve associée ; facture consultable/téléchargeable ; paiement rattaché à facture(s) ; avoir associé à facture initiale.
- Éviter toute carte « aucun document » préremplie si la donnée existe ; si vide, un seul état vide explicite.
- Le **récapitulatif du SPHOT** demeure accessible dans sa rubrique de dossier administratif, sans le confondre avec un devis ou une facture.
- Les documents émis et leurs versions sont conservés sans écrasement.

## 4. Modèle de fonctionnement cible — après validation UI
1. Sélection du périmètre (postes) et simulation par **source publiée unique** `commercialPricingMarkets/FR_ADMIN`, via calcul serveur. Refus si grille absente/invalide.
2. Au passage en commande ferme : **recalcul serveur** des postes, tarifs, version, devise, règle de période et TVA applicable (pas de TVA forcée à 20 % pour l'international). Persister un **instantané immuable** montant, détail tranches, assiette, taxes, preuve CGV, dates, organisme, mode, et identifiant idempotent.
3. CB : paiement hébergé par un prestataire (pas de stockage de carte SPHOT), webhook vérifié, réconciliation, activation automatisée seulement après événement confirmé, suivi remboursement/opposition et renouvellement selon mandat autorisé.
4. Public : commande/engagement juridiquement vérifiable ; contrôle serveur ; activation possible avant paiement selon clauses ; facturation électronique quand réglementairement due (respect du service fait et termes contractuels) ; suivi du paiement/relances. Si preuve non vérifiable : état **à compléter** ou **attente de confirmation** côté organisme, jamais activation sur simple déclaration.
5. Renouvellement 01/01 : le montant annuel et les nouvelles CGV, si pertinentes, doivent être connus avant engagement ; **CB** seulement si mandat récurrent valide et information contractuelle ; **public** seulement si reconduction/engagement juridiquement autorisé. Pas de création automatique d'une obligation nouvelle sans base contractuelle.
6. Séparer `orders`, `subscriptions`, `invoices`, `payments` et journal des événements commerciaux en conservant les schémas déjà présents ; mapping précis à valider avant migration.
7. Mécanismes essentiels : webhooks signés, transactions/idempotence, accès Firestore restreint, journal d'audit, politiques de retry, réconciliation prestataires, période de régularisation, sécurité des webhooks, sauvegardes et contrôle des doubles facturations.
8. Aucun traitement manuel régulier par Super Admin. Les échecs sont traités par services autonomes, message clair à l'Admin et, pour les exceptions impossibles à automatiser, circuit de support/délégation distinct plutôt que supervision obligatoire du Super Admin.

## 5. Écarts techniques constatés au 14/10/2026 (à corriger AVANT paiement réel)
- `lib/web/admin/pages/admin_subscription_panel.dart` : `_fallbackAnnualPricePerStationExclTax = 500.0`, offre = nombre x prix unitaire ; ancien affichage 500 € ; ancienne méthode `_activateSubscription()` peut écrire directement `subscriptions/{uid}.status = active` côté client.
- `lib/web/admin/services/admin_subscription_order_service.dart` : `_defaultPricePerStationExclTax = 500.0`, montant = stations x prix unitaire, TVA locale à 20 %, écrit dans `orders` depuis Flutter. À remplacer par validation transactionnelle serveur fondée sur la grille publiée et règles légales.
- `lib/web/admin/pages/admin_payment_panel.dart` : **aperçu correct** du tarif publié via `PublishedCommercialQuoteService`, mais ne représente pas une commande ni un paiement réel.
- `lib/web/admin/pages/admin_dashboard_page.dart` : anciennes rubriques indépendantes PAIEMENT, ABONNEMENT, DOCUMENTS & FACTURES ; documents financiers majoritairement en présentation statique.
- Vérifier les règles Firestore : **le client ne doit pas pouvoir se donner des droits payants ni créer/altérer des commandes validées au montant arbitraire**.
- **Ne pas déployer/activer le parcours de vente** avant refonte serveur, tests et validation juridique/fiscale.

## 6. Batterie de tests métier attendue
- Nombre de postes 0, 1, 2, 4, 5, 9, 10, 11 ; grille publiée, changement de version, absence de grille ; numéro `idSphot` affiché seulement lorsqu'il existe.
- Première activation 2 janvier / 15 juillet / 31 décembre : plein tarif, échéance au 31/12, puis renouvellement au 01/01 seulement si autorisé.
- CB : paiement confirmé / annulé / refusé / webhook répété / webhook hors ordre / remboursement / litige ; pas de double activation ni double facture.
- Public : pièce vérifiée, pièce manquante, référence arbitraire, service fait, rejet Chorus/PA, paiement tardif, procédure d'escalade sans Super Admin.
- CGV : aucune version publiée, version changée avant confirmation, absence d'acceptation, audit historique.
- Taxes/pays : collectivité FR, organisme privé FR, clients UE et hors UE ; aucun taux de TVA hardcodé sans décision fiscale.
- Les 8 jours d'essai et les SPHOTS visibles sans abonnement restent indépendants et non régressés.

## 7. Décisions encore ouvertes (pas automatiquement validées)
- Mise en page exacte des deux panneaux et leurs libellés finaux ; choix à faire sur la présentation des éléments tarifaires/récapitulatifs.
- Prestataire de paiement CB et prestataire/plateforme de facturation électronique, ainsi que compatibilité Chorus Pro, international.
- Procédure permettant de **vérifier automatiquement** un engagement d'achat public, sans se fier à la seule saisie déclarative.
- Conditions contractuelles exactes de renouvellement de commandes publiques, délais et relances, remboursement, contestations, émission réglementaire des factures.
- Mode de représentation du fiscal avant confirmation (selon situation fiscale SPHOT).
- Validation juridique/comptable finale des CGV, de la tarification sans prorata et des circuits de facturation.

## 8. Références publiques consultées (au 14/10/2026)
- DGFiP, plateformes agréées : https://www.impots.gouv.fr/facturation-electronique-et-plateformes-agreees
- Service Public, facturation marché public : https://entreprendre.service-public.gouv.fr/vosdroits/F23386
- DGFiP, réforme : https://www.impots.gouv.fr/actualite/facturation-electronique

**Important : document d'architecture, aucune modification d'écran, code, Firestore, règlement ou déploiement par ce document.**
