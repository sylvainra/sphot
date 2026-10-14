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

## 9. Décision confirmée et nettoyage commencé le 14/10/2026

**Décision définitive utilisateur :** l'ancienne proposition d'un tarif unique de 500 € HT par poste ne s'applique **plus à aucune nouvelle offre SPHOT ADMIN**. Grille marginale progressive publiée uniquement, conservant les conditions annuelles sans prorata. Les pièces et montants d'anciens contrats effectivement signés ne sont pas modifiés.

**Nettoyage du code réalisé sur la branche de travail (aucun déploiement, aucune migration destructive de Firestore)** :
- `admin_subscription_panel.dart` : retrait du prix unique de 500 €, suppression du calcul local `nombre × prix fixe`, affichage et enregistrement du **brouillon** selon le seul devis simulé de la grille publiée (`pricingReference`, `version`, montant et postes) ; retrait de l'ancienne méthode inutilisée qui pouvait activer l'abonnement côté client. Si la grille est indisponible, aucun montant de remplacement ni enregistrement d'offre.
- `admin_subscription_order_service.dart` : **ancienne confirmation de commande volontairement neutralisée** tant que recalcul/validation serveur, CGV et fiscalité ne sont pas prêts. Ne pas la réactiver sans remplacement sûr ; il n'y a plus de création directe de commande depuis ce service Flutter.
- `admin_trial_request_page.dart` : demande d'accès et essai sans prix unitaire ni TVA de remplacement.
- `admin_dashboard_page.dart` : estimation basée sur `annualAmountExclTax` enregistré, et « tarification à actualiser » si absent ; plus de multiplication par prix unique.
- `functions/admin_workflow.js` : suppression de la constante de prix unique ; les rappels de fin d'essai/renouvellement orientent vers la grille publiée plutôt que d'inventer un montant, et les PDF/brouillons issus d'anciens ordres n'inventent plus 500 € si champ manquant.
- `super_admin_admin_requests_page.dart`, `super_admin_admin_workflow_panel.dart` : le prix fixe n'est plus introduit lors de l'approbation de la demande ou de l'essai.
- `super_admin_dashboard_finances_page.dart` : ancien éditeur de prix unitaire remplacé par un message renvoyant au module de grilles publiées.
- `super_admin_subscriptions_page.dart` : tableaux affichant les totaux annuels enregistrés, sans multiplication par un ancien prix unitaire.

- `super_admin_dashboard_page.dart` : synthèse du coût fondée sur le total enregistré, sans multiplication par tarif unitaire.
- **Attention comptable :** les totaux des anciennes souscriptions ne doivent pas être reconstitués arbitrairement. Si `annualAmountExclTax` est absent, la rubrique affiche une information à actualiser ; les montants historiques réels devront être rapprochés des commandes/factures avant migration.
- La source de prix publiés reste `commercialPricingMarkets/FR_ADMIN`, et la nouvelle confirmation de commande devra utiliser le même calcul serveur ; aucun nouveau montant tarifaire n'est inventé par les écrans.

**Attention** : les nouveaux écrans en deux rubriques et le parcours de commande complet restent **à concevoir puis à coder après validation de la maquette** ; l'ancien parcours de commande est bloqué par sécurité, l'activation CB/commande publique et les CGV ne sont pas encore raccordées. Les données historiques Firestore ne sont pas migrées et les obligations réglementaires doivent être validées par un professionnel. Le SDK Flutter et une compilation/test de l'application n'ont pas été exécutés dans l'environnement de l'assistant. Vérifier la branche et compiler localement avant toute fusion ou déploiement.

## 10. Premier écran ABONNEMENT mis en place pour tests — 14/10/2026

**Version de travail, non déployée :** l'utilisateur a validé les quatre sections et demandé de les mettre en place pour essai dans Chrome. Les modifications sont sur la branche `codex/advertiser-pricing-table-v1`.

- `lib/web/admin/pages/admin_subscription_panel.dart` : quatre accordéons dans l'ordre validé :
  1. POSTES ET OFFRE ;
  2. ORGANISME PAYEUR ;
  3. MODALITÉS DE RÈGLEMENT ;
  4. CONDITIONS ET CONFIRMATION.
  L'offre continue d'utiliser `PublishedCommercialQuoteService.admin` sur la grille publiée, avec libellés comptables par tranches, prix HT, absence de prorata, numéros `idSphot` lorsque renseignés. Les données de facturation existantes sont conservées. Le mode de règlement est enregistré comme **préférence de brouillon**, non comme preuve de paiement ou commande ferme. La sélection modifiée n'apparaît plus comme « renseignée » tant qu'elle n'est pas enregistrée.
- `lib/web/admin/pages/admin_dashboard_page.dart` : menu limité à **ABONNEMENT** et **FACTURES & PAIEMENTS** pour le parcours commercial. L'ancien volet PAIEMENT peut subsister dans le code pendant la migration, sans bouton dédié. La seconde rubrique conserve pour l'instant ses composants historiques en attente de raccordement au vrai journal financier.
- La section 4 affiche les CGV à raccorder et un bouton **CONFIRMER MA COMMANDE** désactivé : pas de CGV fictivement acceptées, pas de fiscalité inventée, pas de création de commande/CB.
- Vérifications statiques des fichiers modifiés : délimiteurs équilibrés, quatre sections présentes, aucune référence UI au tarif unique, l'appel à l'ancien service de commande n'est pas réintroduit. **Compilation Flutter, test navigateur, vérifications Firebase non réalisés par l'assistant (SDK Flutter absent)** ; ils doivent être effectués localement.
- Pour essai local : vérifier `git status`, sauvegarder les changements non committés si nécessaire, puis `git fetch origin`, `git switch codex/advertiser-pricing-table-v1`, `git pull --ff-only origin codex/advertiser-pricing-table-v1`, `flutter pub get`, `flutter run -d chrome -t lib/main_web_admin.dart`.
- Vérifier : menu à deux rubriques, 430 px et icône Fire, accordéons, choix des postes et statuts, tarification 1/2/4/5/9/10 postes, modes de règlement (sans encaissement), sauvegarde du brouillon, bouton final désactivé et aucun document `orders` créé.
- Prochaine phase **après retour visuel** : finaliser organisme payeur multi-pays, affichage réel des CGV publiées et acceptation immuable, taxation selon régime, fonction serveur de commande, authentification des paiements, puis chronologie des vrais documents dans FACTURES & PAIEMENTS. Ne pas modifier l'activation des SPHOTS sans validation.

## 11. Validation visuelle et noms définitifs des étapes 6 et 7 (14/10/2026)

L'utilisateur a testé les écrans dans Chrome avec captures : panneau de 430 px et Fire SVG, accordéons 01–04, montant 499 € HT pour 1 poste, montant 898 € HT pour 2 postes sur grille `FR_ADMIN-V3`, organisme payeur prérempli, choix de modalité de règlement et bouton contractuel désactivé ; le volet financier apparaît toujours sous forme de rubriques provisoires. L'ensemble paraît raccordé visuellement, **mais la validation métier complète n'est pas faite** (CGV, fiscalité, émission de facture et paiements non raccordés).

**Intitulés validés par l'utilisateur** :
- Étape 6 = **ABONNEMENT & PAIEMENT** : souscription, offre et choix/paiement effectif futur.
- Étape 7 = **FACTURES & DOCUMENTS** : consultation des devis/commandes/factures/avoirs et suivi du règlement ; pas de paiement initial dans cette étape.

Changement limité des titres visibles du tableau de bord (boutons et en-têtes) dans `admin_dashboard_page.dart`, et en-tête du vrai volet `admin_subscription_panel.dart`. Le libellé ancien peut subsister dans le suivi documentaire historique comme trace, mais ne doit pas réapparaître dans la navigation client.

La branche utilisée reste `codex/advertiser-pricing-table-v1`. Aucun service de paiement, commande réelle, émission de facture ou validation juridique n'a été activé par le renommage.

**À continuer :** compléter les champs et règles de l'organisme payeur français/étranger, puis rendre la section CGV réellement consultable et acceptable et concevoir la chronologie financière, après validation des écrans.

## 12. Proposition de conception — 02 ORGANISME PAYEUR (14/10/2026, À VALIDER)

Contexte : écran ABONNEMENT & PAIEMENT déjà testé visuellement ; volet FACTURES & DOCUMENTS distinct. La rubrique organisme payeur actuelle préremplit les champs à partir de `adminRequests/{uid}` (facturation, structure, territoire, profil) puis `subscriptions/{uid}`. **ProConnect a été abandonné pour dysfonctionnement et incompatibilité avec l'internationalisation : aucune certification ni exigence d'identité ProConnect ne doit être réintroduite.** Conserver les valeurs commerciales déjà enregistrées, sans effacer les historiques.

### Proposition visible, minimale
1. **Entité à facturer** : case/sélecteur « Identique à la structure gestionnaire du SPHOT » (préremplie si correspondance) / « Autre organisme payeur » pour collectivités ou structures facturant séparément ; toute modification d'entité exige preuve d'habilitation contractuelle avant commande.
2. **Pays de facturation** (France par défaut si attesté, sinon à sélectionner, enregistrer en code pays ISO) ; **nature du payeur** selon catégories « organisme public », « entreprise/organisme privé » ; préremplir d'après organisation enregistrée, mais ne pas assimiler la simple inscription SPHOT à une vérification juridique de l'organisme.
3. **Identification de l'entité** : dénomination complète, SIRET français 14 chiffres et SIREN dérivé/contrôlé 9 chiffres (si France), ou identifiant officiel local selon pays ; identifiant TVA intra-UE seulement si pertinent. Éviter SIRET obligatoire pour les entités étrangères ; ne pas inventer de n° TVA.
4. **Adresse de facturation** : ligne d'adresse, complément facultatif, code postal, ville, pays. Conserver les adresses du lieu de baignade séparées de celles de facturation.
5. **Contact facturation** : nom, email de réception/notification, téléphone facultatif sauf besoin avéré. Contact facturation distinct du profil de connexion SPHOT et du signataire habilité.
6. **Section 03, hors du présent formulaire** : mode de règlement, numéro d'engagement, bon de commande, code service Chorus Pro, règles de routage selon annuaire public ; ne pas dupliquer ces champs dans organisme payeur.
7. **Statuts** : « à compléter », « en cours », « à corriger » et « renseigné et vérifié ». La validation d'un brouillon permet de compléter plus tard, mais aucune commande ferme avec SIRET tronqué / adresse manquante / email invalide / entité sans autorisation. Les vérifications serveur et annuaires sont nécessaires, une simple longueur valide ne prouve pas l'identité.
8. **International** : sélection pays pilote les champs d'identification et validation par pays ; enregistrer code ISO, identifiants et règles de facturation, mais devise et traitement TVA issus du catalogue tarifaire et du moteur fiscal, pas modifiables arbitrairement par le client.
9. **Historisation** : copie de l'organisme facturé, identifiants, adresse et coordonnées au moment de la commande, sans réécriture des factures émises quand le client modifie son profil ultérieurement. Séparer le compte de connexion SPHOT du `billingProfile` modifiable ; aucun champ ProConnect certifié n'est requis. Un changement de payeur peut nécessiter de reprendre l'étape contractuelle.

### Audit code pour implémentation après validation
- `lib/web/admin/pages/admin_subscription_panel.dart`, `_mergeRegistrationData` reprend les valeurs du dossier et `_payerForm` propose 9 champs.
- Aujourd'hui `payerComplete` se limite à 7 valeurs non vides ; ni validation 14 chiffres SIRET, ni email, ni code postal, ni logique selon pays. Les captures ont un SIRET de quatre caractères (« 0123 »), ainsi qu'adresse et code postal vides. Cet état ne doit pas devenir « renseigné/vérifié ».
- Conserver le bouton ENREGISTRER comme **sauvegarde de brouillon** (sans contrat). Ajouter retour d'erreur et message de succès (la méthode `_saveSection` masque actuellement toutes erreurs).
- Les contrôles réglementaires doivent être confirmés avec le prestataire de facturation, le régime du vendeur SPHOT et les CGV avant transaction réelle ; ne jamais coder un taux de TVA général à 20 % comme vérité internationale.

### Références officielles vérifiées
- Chorus Pro annuaire destinataires publics et champs obligatoires conditionnels : https://portail.chorus-pro.gouv.fr/aife_documentation?id=kb_article_view&sysparm_article=KB0011481
- Chorus Pro plateforme publique depuis 2026 : https://www.economie.gouv.fr/actualites/chorus-pro-restera-la-plateforme-de-reference-pour-la-facturation-electronique-du
- Mentions obligatoires factures : https://entreprendre.service-public.gouv.fr/vosdroits/F31808
- Réforme et plateformes agréées : https://entreprendre.service-public.gouv.fr/actualites/A15683

**Statut : proposition métier à soumettre à l'utilisateur, PAS de modification du formulaire Flutter effectuée à cette étape.**

## 13. Confirmations définitives (14/10/2026)
- **ProConnect supprimé du périmètre du portail SPHOT ADMIN** : abandon lié au non-fonctionnement constaté et à la nécessité d'une ouverture internationale. Ne pas exiger de ProConnect, ne pas le présenter comme une identité certifiée et ne pas y rattacher l'autorisation de facturation. Le code hérité du dépôt peut contenir d'anciens champs, mais le nouveau parcours doit s'appuyer sur le compte SPHOT et sur les données d'organisation/facturation vérifiées par des moyens adaptés.
- **Le payeur peut être une entité juridique différente de l'organisme qui gère les SPHOTS**. Deux choix explicites dans la rubrique 02 : organisme gestionnaire (par défaut) ou autre organisme payeur. Le deuxième choix doit demander les données du payeur, non réutiliser silencieusement les identifiants juridiques du gestionnaire. Habilitation à vérifier avant commande ferme.
- La rubrique 02 est validée dans son principe. La commande réelle et le paiement restent désactivés jusqu'à mise en œuvre des CGV, des contrôles serveurs et de la facturation électronique.
