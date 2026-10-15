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

## 14. Rubrique 02 — correction effective du parcours payeur (14/10/2026)

À la suite de la confirmation de l'utilisateur :
- ProConnect est abandonné et n'est **plus utilisé comme source de préremplissage dans la section ORGANISME PAYEUR**. Les anciens champs d'autres parcours ne sont pas effacés par cette intervention.
- Le payeur peut être **l'organisme gestionnaire** (préremplissage via le dossier SPHOT existant) ou **un autre organisme** (fiche distincte, sans recopie silencieuse des informations du gestionnaire). Les brouillons non enregistrés de chaque choix sont séparés pendant la session de saisie.
- Champs de facturation : dénomination, catégorie public/privé, pays, SIRET français (format strict 14 chiffres) OU identifiant officiel d'organisme étranger, TVA si applicable, adresse et complément, code postal élargi, ville, contact, email et téléphone facultatif.
- La rubrique affiche **À CORRIGER** si un SIRET français enregistré est mal formé ou si l'adresse email ne correspond pas à un format de base ; **RENSEIGNÉ** signifie uniquement champs obligatoires remplis et format plausible, **pas vérification de l'existence juridique**.
- L'enregistrement reste un **brouillon** et affiche désormais un retour succès/échec. Les entrées vides du payeur distinct ne sont jamais remplacées par l'ancien gestionnaire lors de la fusion des données d'inscription. SIREN dérivé seulement d'un SIRET au bon format ; aucune certification officielle n'est prétendue.
- Le pays déclenche l'affichage adapté du SIRET français ou de l'identifiant étranger ; le contrôle complet des codes pays internationaux, la validité fiscale/annuaire, les habilitations et le traitement TVA restent réservés au moteur serveur et au prestataire de facturation.
- La rubrique 03 conserve les codes service Chorus Pro / numéros d'engagement et de bon de commande ; la rubrique 04 conserve la confirmation verrouillée.
- **Évolutions encore nécessaires** : conformité réglementaire à confirmer, vérification d'identité juridique et de l'autorisation d'un payeur tiers, historisation de la photo du payeur lors de la commande/facture, moteur fiscal et facturation électronique, CGV publiées et acceptées.

Modifications sur `lib/web/admin/pages/admin_subscription_panel.dart` dans `codex/advertiser-pricing-table-v1`, sans fusion ni déploiement. Contrôles statiques de délimiteurs et de présence du formulaire effectués ; **aucune compilation Flutter ni test de navigateur réalisé côté assistant**.

Test conseillé : cas prérempli mairie française avec SIRET de 4 chiffres (doit être signalé), passage à autre organisme (nom et SIRET vierges), remplissage d'un SIRET 14 chiffres et adresse, choix pays non français (identifiant officiel local à la place du SIRET), retour au gestionnaire sans pollution des champs, enregistrement brouillon et réouverture, confirmation de commande toujours inactive.

## 15. Test visuel — menu organisme payeur et devise officiel (14/10/2026)

**Retour utilisateur :**
- Le menu déroulant « Nature de l'organisme » est grisé avec une apparence standard Flutter, contrairement aux autres menus SPHOT. Il doit suivre le modèle de la page de demande d'accès (fond blanc, bord bleu, option bleu soutenu, chevron rouge).
- La rubrique **DEVIS** de l'étape 7 « FACTURES & DOCUMENTS » affiche « AUCUN DOCUMENT », mais aucune commande d'émission de devis n'existe dans le parcours Admin. L'utilisateur confirme qu'un vrai devis est indispensable même si certains organismes n'en ont pas besoin pour commander.

**Réalisations techniques limitées :**
- `lib/web/admin/pages/admin_subscription_panel.dart` : remplacement du `DropdownButtonFormField` natif par un sélecteur visuellement aligné sur le composant existant de `admin_trial_request_page.dart` (OverlayEntry, carte blanche, bord bleu, chevron rouge, libellés bleus). Fermeture au clic extérieur, à la sélection, au changement d'organisme ou à la fermeture du panneau. Aucun changement de données fiscales ou tarifaires.
- `lib/web/admin/pages/admin_dashboard_page.dart` : la rubrique DEVIS indique « ÉMISSION NON ENCORE DISPONIBLE » au lieu d'affirmer que la liste a été consultée et est vide ; information provisoire véridique, pas de faux devis.
- Aucune émission de devis, aucun ordre, paiement ni PDF commercial n'a été déclenché par ces changements.

**Audit du devis existant :**
- Le service `PublishedCommercialQuoteService.admin` et la Cloud Function `previewPublishedCommercialQuote` fournissent une **SIMULATION HT uniquement**, avec version de grille publiée et tranches, et n'écrivent ni devis ni commande dans Firestore.
- `functions/index.js` fournit déjà `assignQuoteNumberOnWrite` pour `quotes/{quoteId}` et la numérotation transactionnelle `DV-{ANNEE}-{ADHERENT}-{SEQUENCE}`, selon `docs/numerotation_documents_commerciaux.md`. Le déclencheur attribue un numéro si le document contient une référence admin admissible. **Cela ne suffit pas pour créer un devis contractuel** : il n'existe pas à ce stade de flux Admin qui crée un devis contrôlé côté serveur, lui associe le bon émetteur/payeur, le traitement fiscal, la date de validité, un PDF de marque SPHOT, et une consultation depuis le portail.
- Ne pas générer un numéro ou PDF contractuel automatiquement lors de la simple simulation, afin de ne pas polluer la séquence des devis émis.

**Parcours devis proposé, à valider avant codage :**
1. Dans **ABONNEMENT & PAIEMENT**, un bouton **ÉTABLIR UN DEVIS**, facultatif, après sélection des postes et renseignements obligatoires de l'organisme payeur. L'Admin peut continuer directement à la commande sans devis.
2. Fonction serveur authentifiée et transactionnelle : vérification organisation/périmètre, recalcul avec la grille **PUBLIÉE** en vigueur, version et tranches, année civile sans prorata, statut fiscal et montants HT / taxes / TTC (ou autres mentions légales) adaptés au pays et à l'entité émettrice ; sans moteur fiscal validé, **ne pas émettre**.
3. Création et numérotation via infrastructure existante `quotes` / `DV-...` ; document horodaté, référence dossier, destinataire, sélection SPHOTS, période concernée, validité/conditions contractuelles à définir, identifiant de génération idempotent, et **copie immuable** des valeurs du moment.
4. PDF SPHOT signé « L'équipe SPHOT » avec charte documentaire commune, consultation/téléchargement de l'original depuis **FACTURES & DOCUMENTS**. Pas de statut « devis émis » avant présence du PDF et numéro cohérents. Pas de suppression/écrasement de documents émis.
5. Devis `issued`, `expired`, `superseded` ou `accepted` selon règle à définir ; un changement de prix, nombre de postes ou payeur exige nouveau devis plutôt que mutation silencieuse.
6. Lors de la souscription, possibilité de rattacher le devis en vigueur à la commande, mais montant/recalcul serveur à vérifier à l'engagement selon règles de validité. **Devis ≠ paiement ≠ commande ≠ activation des SPHOTS.**
7. Aucun contrôle financier courant requis du Super Admin ; traitement automatisé de bout en bout, erreurs renvoyées à l'Admin de façon explicite.

**À valider avec l'utilisateur :** emplacement du bouton devis dans l'étape 6 après l'offre et l'identité du payeur ; absence de devis obligatoire ; règles de validité, émission des PDF et acceptation sans signature électronique obligatoire si le circuit de commande publique est utilisé.

**Compilation et test navigateur de la personnalisation du menu restent à réaliser localement.**

## 16. Devis AVANT règlement et distinction des numéros — décision utilisateur 14/10/2026

**Retour utilisateur** : le numéro de commande doit-il se générer automatiquement ? Le numéro d'engagement juridique est-il intrinsèque à l'Admin ? Le devis doit être présenté **entre l'ancienne étape 02 ORGANISME PAYEUR et l'ancienne étape 03 MODALITÉS DE RÈGLEMENT**.

**Clarification métier approuvée comme principe d'organisation** :
- Référence du dossier Admin SPHOT : attribuée par SPHOT lors de l'inscription/dossier. Elle n'est ni commande, ni devis, ni engagement juridique du client.
- **Numéro de devis SPHOT** : attribué automatiquement à l'émission par le système documentaire existant `quotes/{quoteId}` / `assignQuoteNumberOnWrite`; modèle `DV-{ANNEE}-{ADHERENT}-{SEQUENCE}`.
- **Numéro de commande SPHOT** : attribué automatiquement lors de la confirmation contractuelle effective (pas au choix du mode de règlement ni à la simulation), par `orders/{orderId}` / `assignOrderNumberOnWrite`, modèle `CMD-{ANNEE}-{ADHERENT}-{SEQUENCE}`.
- **Bon de commande externe de l'organisme** (`purchaseOrderNumber`) : émis ou communiqué par le client public, ne doit pas être inventé par SPHOT.
- **Numéro d'engagement juridique externe** (`engagementNumber`) : propre à un engagement/contrat/commande du payeur, pas intrinsèque au compte Admin ; peut coïncider avec le numéro du bon de commande ou du marché. Un numéro déjà stocké peut être prérempli pour le brouillon mais ne doit pas être réutilisé automatiquement sur une nouvelle période sans vérification.
- **Code service Chorus Pro** : généralement associé au service de l'entité publique destinataire. Nécessaire selon les règles de routage du destinataire (voir annuaire Chorus) ; ne pas imposer aveuglément les trois champs à tous les organismes. Le cochage « aucun bon de commande exigé » ne prouve pas à lui seul l'engagement.
- Source officielle Chorus Pro, guide de lecture annuaire : https://communaute.chorus-pro.gouv.fr/documentation/guide-de-lecture-de-lannuaire-des-entites-publiques/

**Nouvel ordre validé par la préférence explicite de l'utilisateur**, appliqué dans l'interface sur la branche :
1. `01 — POSTES ET OFFRE` — simulation et sauvegarde de l'offre.
2. `02 — ORGANISME PAYEUR` — identité commerciale/facturation.
3. `03 — DEVIS (FACULTATIF)` — avant tout règlement. À terme établissement, numérotation, PDF et archivage.
4. `04 — MODALITÉS DE RÈGLEMENT` — choix CB ou commande publique, saisie des références fournies par le payeur si elles sont nécessaires.
5. `05 — CONDITIONS ET CONFIRMATION` — CGV, fiscalité, engagement.

**État actuel des fonctions** : le nouveau panneau DEVIS est placé au bon endroit avec un bouton `ÉTABLIR UN DEVIS` encore désactivé, car il faut construire la création contractuelle côté serveur, le calcul fiscal, l'édition du PDF et la consultation de l'original. La commande réelle reste également désactivée. Le devis **n'est pas obligatoire** pour passer directement au règlement/à la commande. Le changement des numéros n'a pas modifié les écritures Firestore. Aucun nouveau devis n'a été produit. **Ne pas présenter ce stade comme une émission de devis fonctionnelle.**

**À décider avant développement de l'émission** : durée de validité des devis (suggestion à faire à l'utilisateur : 30 jours, mais jamais plus tard que la fin de l'année concernée sans reconfirmation des conditions), régime TVA applicable au vendeur SPHOT en France et à l'international, contenu final du PDF. Toute modification de grille tarifaire publiée après émission doit préserver l'historique/conditions de validité d'un devis signé.

## 17. VALIDÉ — Validité des devis SPHOT ADMIN : 30 jours (14/10/2026)

**Décision explicite utilisateur :** validité de **30 jours calendaires** pour un devis officiel, limitée au **31 décembre de l'année d'abonnement concernée**. Le devis est facultatif, placé en étape 03 avant les modalités de règlement, et ne déclenche jamais de paiement/activation.

**Convention technique pour lever l'ambiguïté :** jour d'émission compté comme **premier jour**, dernier jour de validité **inclus**. Exemples :
- Devis émis le 14/10/2026 pour 2026 → valable jusqu'au **12/11/2026 inclus**.
- Devis émis le 20/12/2026 pour 2026 → valable jusqu'au **31/12/2026 inclus**.
- Devis émis le 14/10/2026 pour une année ultérieure → expiration à 30 jours (sous réserve que prix/conditions de cette année soient publiés et légitimes).
- Aucune proratisation, et l'expiration du devis n'est pas la date de fin de l'abonnement.

**Code ajouté :**
- `functions/admin_quote_validity.js` : fonction pure `quoteValidityForCalendarYear(issuedOn, subscriptionYear)`, date `AAAA-MM-JJ`, règle 30 jours et plafond 31 décembre, exception si date/année invalide. Ce calcul DOIT être invoqué côté serveur lors de la création réelle d'un devis et son résultat figé dans le document.
- `functions/test/admin_quote_validity.test.js` : cinq scénarios de non-régression (30 jours, plafond 31 décembre, année bissextile, année suivante, date invalide).
- `lib/web/admin/pages/admin_subscription_panel.dart` : texte informatif de validité dans 03 — DEVIS (FACULTATIF).

**Statut technique sans ambiguïté :** aucun devis officiel ni PDF généré à ce jour. Le bouton d'émission reste désactivé. Le moteur de prévisualisation n'est pas un devis contractuel. Il manque **la personne morale émettrice réelle** de SPHOT et ses informations fiscales, le calcul/traitement fiscal approprié, les conditions et mentions obligatoires et le serveur authentifié de création+PDF+archivage. Ne pas coder de raison sociale, de numéro SIRET de l'émetteur ou de taux de TVA fictifs. Aucun paiement réel ni abonnement activé.

**Vérifications encore nécessaires :** tests Node `node --test functions/test/admin_quote_validity.test.js` dans l'environnement du projet, puis tests Flutter de présentation. Aucun service n'a été déployé.

## 18. Reprise développement après réflexion juridique — aperçu PDF sans société émettrice (14/10/2026)

L'utilisateur conserve son emploi CMA Formation à temps complet pendant 1–2 ans et sollicite les RH sur le cumul et les possibilités de créer une SASU. **SPHOT n'est PAS encore immatriculé** : aucun SIRET émetteur, régime TVA ni société émettrice ne doivent être fictivement affichés dans un devis contractuel. Le développement et les tests du projet se poursuivent sans émettre de documents commerciaux opposables.

**Implémentation expérimentale :**
- Nouveau fichier `lib/web/admin/services/admin_quote_simulation_pdf_service.dart` : production locale en Flutter d'un PDF de **SIMULATION TARIFAIRE — NON CONTRACTUELLE**, avec le `pdf` et le partage `share_plus` déjà présents, aucune dépendance à installer. Le document indique clairement qu'il ne vaut ni devis, ni facture, ni bon de commande ; aucun numéro DV, aucune date d'émission de devis officiel, aucune signature commerciale et aucune TVA arbitraire ne sont fabriqués.
- `lib/web/admin/pages/admin_subscription_panel.dart`, étape `03 — DEVIS (FACULTATIF)` : second bouton **TÉLÉCHARGER LA SIMULATION PDF** utilisable après sauvegarde de l'offre ; le bouton contractuel **ÉTABLIR UN DEVIS** reste désactivé. Les coordonnées de payeur provenant du dossier enregistré, les postes référencés, le détail des tranches HT, référence de la grille publiée, année civile, absence de prorata et principe de validité à 30 jours sont reportés dans l'aperçu. L'absence de champs de payeur est explicitement marquée « À compléter » dans ce document préparatoire.
- Au clic, nouveau calcul du tarif par `PublishedCommercialQuoteService.admin` ; si la référence ou le total a changé depuis la sauvegarde de l'offre, **refus avec message invitant à réenregistrer l'étape 01** plutôt que diffusion d'un ancien montant. Test local uniquement, sans écritures dans `quotes`, `orders`, `invoices`, `documents`, `subscriptions` ni activation.
- Le service de génération vérifie la cohérence des quantités et des lignes avec le total publié. Le PDF indique expressément que les taxes et montant TTC restent non déterminés.
- Les données du PDF sont partagées seulement à l'initiative de l'Admin et ne sont pas archivées dans Firestore à ce stade.
- Le moteur officiel futur réutilisera une fonction serveur authentifiée, une identité d'émetteur immatriculée, une fiscalité déterminée et la numérotation `DV-...` ainsi que le registre documentaire existants. Le prototype Flutter ne devient pas automatiquement le générateur officiel.

**À tester localement dans Chrome** : enregistrer au moins un poste dans l'étape 01 ; ouvrir 03 ; cliquer TÉLÉCHARGER LA SIMULATION PDF ; vérifier document lisible, montant HT, poste, organisme, mentions NON CONTRACTUEL, absence de numéro officiel, aucun document Firestore créé ; changer la sélection non sauvegardée et vérifier que le bouton s'inactive ; tester la grille publiée indisponible. `share_plus` peut déclencher un téléchargement ou une boîte de partage selon navigateur.

**Vérifications réalisées par l'assistant** : lecture du code du PDF Flutter existant (sauveteurs) pour reprendre ses APIs, contrôles statiques de délimiteurs et de la non-écriture Firestore, vérification documentaire de l'API `pdf`. Pas de SDK Flutter disponible : **aucune compilation Flutter, ni rendu effectif du PDF Flutter, ni test Chrome n'a pu être effectué**.

**Limites des étapes ultérieures** : identité juridique de SPHOT à définir après démarche RH et immatriculation, taux et mécanisme TVA, mention de validité datée, fiscalité internationale, commande/CGV et preuve d'engagement, PDF officiel serveur vérifiable, chronologie FACTURES & DOCUMENTS.

## 19. Essai Chrome validé et corrections de PDF (14/10/2026, 13h55 Paris)

Quatre captures de l'utilisateur confirment :
- deux postes `LONGE 09 - PLAGE DU ROCHER` et `LONGE 13 - PLAGE DES CONCHES` sélectionnés ; grille publiée `FR_ADMIN-V3`, **499 + 399 = 898 € HT** et étape 01 « RENSEIGNÉ » ;
- étape 03 DEVIS et bouton de simulation visible et utilisable ; fenêtre Windows « Partager » ouverte avec fichier `SPHOT_SIMULATION_ADMIN_20261014.pdf` de 6,9 Ko ;
- le PDF est effectivement généré sur son poste mais **présente des apostrophes et certains glyphes superposés**, donc maquette PDF non validée ; les données de payeur contiennent aussi le **SIRET factice/incomplet `0123`** ;
- l'émission de devis officiel est toujours verrouillée, à raison, car SPHOT n'est pas immatriculé.

**Correctifs engagés sur la branche** :
1. `lib/web/admin/services/admin_quote_simulation_pdf_service.dart` : retrait des apostrophes typographiques des littéraux du PDF (non prises en charge de façon fiable par la police standard utilisée), nettoyage similaire des valeurs dynamiques, espacement de lignes pour les paragraphes longs, et distinction explicite `FORMAT INVALIDE` pour un SIRET à moins de 14 chiffres (y compris `0123`). Un SIRET de 14 chiffres est seulement au **format plausible / non vérifié**. Aucun contrôle officiel SIRENE n'est prétendu.
2. Export Web réel : `lib/web/admin/services/admin_quote_pdf_export.dart` avec import conditionnel, `admin_quote_pdf_export_web.dart` (lien Blob + attribut `download` dans Chrome), `admin_quote_pdf_export_stub.dart` (partage natif sur les autres plateformes). Le bouton conserve son intitulé « TÉLÉCHARGER LA SIMULATION PDF » et ne doit plus ouvrir Windows Partager sur le Web.
3. Le générateur reste **strictement non contractuel**, sans numéro officiel, aucun taux de TVA inventé, aucune écriture dans Firestore et aucune activation.

**Précaution** : contrôles statiques, mais compilation Flutter et inspection du **nouveau** PDF impossible sans le SDK Flutter / navigateur local. Il faut réexécuter Chrome et regarder si l'espacement et les glyphes sont désormais correctement rendus. Si les défauts persistent, envisager intégration d'une fonte Unicode autorisée dans les assets Flutter, puis tests multi-rendu PDF ; ne pas valider le PDF actuel comme modèle de devis final.

**Prochaine phase** : maquette visuelle SPHOT commune aux documents officiels, système émetteur immatriculé, calcul fiscal sécurisé et archivage du devis officiel numéroté.

## 20. Charte PDF — vrai bandeau du site + marker SVG Fire au pied (14/10/2026)

**Demande explicite utilisateur** : ne pas préparer de maquette théorique, **modifier directement le PDF et tester**. Réutiliser un **header identique à celui du site SPHOT** et le **marker red fire icon SVG centré en bas**, dans l'esprit des emails SPHOT.

**Vérification des sources graphiques dans la branche :**
- Le document imprimable existant `lib/web/admin/pages/sphot_admin_summary_page.dart` utilise en header une carte `data/images/map_background.jpg` et l'image du titre `data/icons/title.png` centrée.
- `functions/sphot_email_design.js` utilise la marque SPHOT en haut et le Fire rouge centré en fin de mail.
- Le marker exact est `data/icons/fire_red_icon.svg`.

**Implémentation faite** dans `lib/web/admin/services/admin_quote_simulation_pdf_service.dart` :
1. Chargement via `rootBundle` des deux images graphiques de l'en-tête du site et du SVG du marker ; pas de copie inventée ni de police utilisée pour simuler le vrai titre du site.
2. Bandeau image de 76 points de hauteur avec carte en fond (`pw.Image`, `BoxFit.cover`) et titre SPHOT superposé au centre (`pw.Image`, `BoxFit.contain`). `DOCUMENT DE PRÉPARATION` est présenté séparément sous le bandeau.
3. Pied de chaque page : `pw.SvgImage(svg: fireSvg)` **vectoriel** centré (24 x 38 points), signature `L'équipe SPHOT`, trait bleu fin, mention NON CONTRACTUELLE et pagination.
4. Aucun changement aux montants publiés (exemple courant : deux postes = 898 € HT), aux données de postes/payeur, au format de SIRET, au téléchargement du PDF ou au statut documentaire.
5. Aucun numéro officiel de devis, aucune TVA fictive, aucune création de commande, facture, abonnement, ou droit commercial.

**Tests réalisés** : recherche des assets référencés et contrôle de leur existence via GitHub, revue des composants `pw.Stack`, `pw.Positioned.fill` et `pw.SvgImage` via documentation de la dépendance PDF, contrôle statique des délimiteurs, référence des trois assets, et conservation du bouton officiel désactivé. **Flutter n'est pas disponible côté assistant : pas de compilation ni de test du rendu Web effectué.**

**Essai à faire sur ordinateur** : `git pull --ff-only origin codex/advertiser-pricing-table-v1` puis `flutter run -d chrome -t lib/main_web_admin.dart` ; étape 03 -> TÉLÉCHARGER LA SIMULATION PDF ; vérifier bandeau cartographique/titre au centre, marker rouge SVG net au centre du footer (une page), absence de débordement et maintien des lignes, prix et mentions non contractuelles. Si le gros SVG d'origine provoque une exception de parser ou dépassement, recueillir l'erreur exacte avant toute adaptation de rendu.

**Principe à généraliser APRÈS validation** : même header + signature Fire pour tous les documents administratifs et commerciaux SPHOT, sans refonte structurelle non demandée.

## 21. Capture du PDF avec charte SPHOT — taille du Fire (14/10/2026)

La capture utilisateur confirme que le bandeau du site est désormais bien présent en tête du PDF, avec le titre SPHOT réel sur fond de carte, et que le marker SVG rouge est effectivement centré en bas. Le document est lisible sur une page, avec les deux postes et le total **898 EUR HT** issus de `FR_ADMIN-V3`. Le SIRET incomplet `0123` y est signalé **FORMAT INVALIDE** ; aucun devis contractuel n'est émis.

**Ajustement visuel réalisé après inspection** : marker du pied agrandi de 24 x 38 à **42 x 65 points**, pour retrouver la proportion utilisée dans les courriels SPHOT (42 x 65 px) ; réduction des séparations verticales du contenu de 16 à 10 points et de l'espace après bandeau de 18 à 14 pour limiter le risque de débordement ou de passage à deux pages. Le titre graphique, le fond et les informations commerciales ne sont pas modifiés.

**À vérifier dans Chrome** : rendu sur une seule page, absence de chevauchement entre l'encadré rouge non contractuel et le nouveau marker, centrage et lisibilité de « L'équipe SPHOT ». Aucun test de compilation Flutter ou de PDF rendu n'a été effectué sur la machine de l'assistant.

## 22. Validation partielle et corrections demandées sur simulation PDF (14/10/2026 soir)

Après capture d'une version à titre seul sur fond blanc, l'utilisateur a expressément demandé **sans maquette supplémentaire** :
- retirer tout **contour bleu autour du titre SPHOT**, conserver le titre graphique centré **sans fond carte** ;
- conserver le Fire rouge SVG centré (42 x 65 points) au pied mais **retirer le texte « L'équipe SPHOT » situé en dessous** (cette exception vaut pour la signature visuelle du PDF, sans annuler la signature historique des courriers administratifs) ;
- remplacer `POSTES CONCERNÉS` par `SPHOTS CONCERNÉS`, avec 3 colonnes : **numéro SPHOT si fourni (sinon non attribué)**, **type = Poste de secours** et **nom du lieu**, sans recopier le préfixe du numéro deux fois ;
- renommer seulement le titre de la rubrique `ORGANISME PAYEUR` en **SPHOT ADMIN - COORDONNÉES DE FACTURATION**, tout en conservant les renseignements effectifs de la personne morale facturée (qui peut différer de l'organisme gestionnaire). SPHOT ADMIN seul ne saurait remplacer la dénomination juridique obligatoire du client sur les futures factures ;
- distinguer clairement **la référence du dossier administratif** `SPHOT-ADM-2026-000001` du **numéro de devis DV** : le PDF de simulation indique « Numéro de devis : non attribué (simulation non contractuelle) ». Un numéro `DV-...` ne sera attribué que par l'émetteur officiel serveur quand les conditions légales et fiscales seront réunies, sans jamais le fabriquer localement ;
- forcer tous les textes ordinaires en bleu SPHOT et les textes d'avertissement/totaux en rouge, **aucun texte noir par défaut**.

**Code modifié dans** `lib/web/admin/services/admin_quote_simulation_pdf_service.dart` sur `codex/advertiser-pricing-table-v1`. Le bandeau cartographique n'est plus chargé, aucun contour n'est dessiné autour du titre ; le pied reste vectoriel et centré. L'offre reste la simulation publiée, aucun changement du calcul ou du prix. Aucun devis, commande, facture ou activation produit.

**Contrôles statiques** : délimiteurs équilibrés ; présence du titre sans carte/contour, absence de signature textuelle au pied ; **tous les appels `pw.Text` contiennent maintenant explicitement un style bleu ou rouge**, ainsi que les 3 colonnes et les deux références distinguées. **Compilation Flutter et rendu PDF visuel encore à tester sur le poste de l'utilisateur**.

**Fondement documentaire** : sur une facture l'identité réelle du client/acheteur doit être conservée, quel que soit le libellé marketing de la section ; https://www.service-public.gouv.fr/entreprendre/vosdroits/F31808.

## 23. Décision définitive : SUPPRESSION de la simulation PDF, devis unique (14/10/2026 soir)

**Instruction explicite de l'utilisateur :** une simulation tarifaire téléchargeable fait double emploi avec le devis et complexifie inutilement SPHOT. **La supprimer entièrement** ; ne conserver **qu'un vrai devis officiel** comme document commercial facultatif, sans « usine à gaz », dans le respect des mentions légales applicables.

**Règle finale :**
- **Étape 01 — POSTES ET OFFRE** : les postes de secours sélectionnés, les paliers de la grille tarifaire publiée, les montants HT et la période annuelle restent affichés directement dans l'interface. **Ceci est un aperçu tarifaire à l'écran, sans PDF ni document autonome**. Le bouton ENREGISTRER conserve la sélection en brouillon ; aucun paiement/abonnement n'est créé.
- **Étape 02 — ORGANISME PAYEUR** : véritable identité du client et coordonnées de facturation.
- **Étape 03 — DEVIS (FACULTATIF)** : **un seul bouton « ÉTABLIR UN DEVIS »**, actuellement désactivé tant que SPHOT n'est pas immatriculé et que le traitement fiscal, l'identité émettrice, le contrôle serveur et la génération de PDF officiel ne sont pas opérationnels. Le devis, **une fois émis légalement**, sera numéroté automatiquement `DV-...`, valable **30 jours calendaires maximum, sans dépasser le 31 décembre de l'année concernée**, et historisé dans FACTURES & DOCUMENTS. Jamais de devis obligatoire pour souscrire si le client n'en a pas besoin.
- **Étape 04 — MODALITÉS DE RÈGLEMENT** puis **05 — CONDITIONS ET CONFIRMATION** inchangées, paiement/commande réels toujours verrouillés à ce stade.
- La numérotation `SPHOT-ADM-...` est celle du **dossier administratif**, jamais celle d'un devis. Aucune fausse référence `DV-...` n'est générée.

**Code supprimé sur la branche** `codex/advertiser-pricing-table-v1` :
- import, champ d'état, méthode de partage et bouton de simulation dans `lib/web/admin/pages/admin_subscription_panel.dart` ;
- fichiers devenus orphelins `lib/web/admin/services/admin_quote_simulation_pdf_service.dart`, `admin_quote_pdf_export.dart`, `admin_quote_pdf_export_web.dart`, `admin_quote_pdf_export_stub.dart`.

**Ce qui reste** : `PublishedCommercialQuoteService` et ses fonctions sécurisées de consultation de la grille publiée, car **le calcul du prix à l'écran est nécessaire**, et `functions/admin_quote_validity.js` et ses tests (validité du FUTUR devis officiel). Les anciennes sections 18 à 22 de ce document sont de l'**historique** et ne correspondent plus à un PDF de simulation présent dans le code. Ne pas le rétablir.

**Conformité future du devis** : émetteur identifié officiellement, client facturé correctement, prestations/SPHOTS, conditions (période calendaire sans prorata, validité 30 jours), prix HT et fiscalité applicable déterminée, références/document unique et horodatage, version du tarif publié, document conservé sans écrasement. Seules les mentions légalement pertinentes seront ajoutées au PDF, pas de documents parallèles ni de contrôles commerciaux quotidiens du Super Admin.

**Contrôle demandé** : l'utilisateur doit constater l'absence totale du bouton et de la simulation PDF dans l'étape 03, la présence du seul bouton devis désactivé, et la conservation de l'affichage tarifaire en étape 01. Aucun test Flutter/Chrome réalisé côté assistant.

## 24. Correctif saisis champs facturation — perte du focus après chaque lettre (15/10/2026)

Capture utilisateur de la rubrique 02 « AUTRE ORGANISME PAYEUR » : saisie de « mai » dans la dénomination impossible de façon continue, l'Admin doit recliquer après chaque lettre. Dysfonctionnement constaté dans les champs de saisie du panneau.

**Cause dans `lib/web/admin/pages/admin_subscription_panel.dart` :** `_field()` donnait au `TextFormField` une `ValueKey` incluant `_fieldValue(...)` (le texte entré). Les reconstructions du formulaire (notamment `liveUpdate` pour le pays et toute actualisation réactive des données) remplaçaient le widget lorsqu'une lettre changeait la valeur ; focus et curseur perdus.

**Correction appliquée** : `ValueKey<String>('payer-field-$field-${_payerRelation(data)}')` — identité stable pendant la frappe, différente seulement si l'Admin change de relation payeur. La valeur saisie reste conservée dans `_draft`; `liveUpdate` sur le pays garde l'affichage conditionnel SIRET français / identifiant étranger sans reconstruire le champ à chaque caractère. Tous les champs texte de la rubrique reposent sur `_field()`, donc correctif commun. Aucun changement des données Firestore, contrats, tarifs ou des sections.

**Vérifications** : relecture de tous les `TextFormField` du fichier, la clé ne contient plus de texte évolutif et les champs utilisent `_field()`; inspection statique. Pas de Flutter local chez l'assistant. **À tester dans Chrome** : saisir plusieurs mots dans « Dénomination », adresse, SIRET, contact, email et pays en continu ; choisir « Autre organisme payeur », revenir au gestionnaire, puis revenir au payeur distinct ; enregistrer et vérifier l'absence de perte de focus / de caractères / de mélange entre organismes. Aucune commande ni paiement réels actifs.

## 25. Développement du véritable DEVIS SPHOT ADMIN — première base serveur (15/10/2026)

Demande explicite « poursuivons » après validation du parcours 01 à 05 et constat qu'un formulaire payeur « RENSEIGNÉ » n'active pas le devis : **SPHOT n'est pas immatriculé**, la fiscalité de l'émetteur et la vérification juridique du payeur ne sont pas prêtes.

**Objectif de ce chantier : un seul devis officiel (pas de simulation PDF), facultatif**, valable **30 jours maximum** sans dépasser le 31 décembre de l'année concernée ; numéro `DV-{ANNÉE}-{ADHÉRENT}-{SÉQUENCE}` attribué au serveur via le mécanisme déjà existant `assignQuoteNumberOnWrite`, puis conservation dans FACTURES & DOCUMENTS.

**Code ajouté sur** `codex/advertiser-pricing-table-v1` :
- `functions/admin_quote_issue_readiness.js` : fonction pure de vérification des préconditions d'émission, SANS écriture Firestore. Elle exige l'identité de l'émetteur légalement vérifiée, une autorisation explicite de mise en production, le vrai payeur contrôlé (et son habilitation si différent du gestionnaire), les SPHOTS éligibles au périmètre Admin, la grille publiée recalculée au serveur, une fiscalité documentée et contrôlée au centime HT/taxes/TTC et la validité de 30 jours. Les marques de « vérifié » ne doivent jamais provenir des données client modifiables : elles devront être construites exclusivement par le futur endpoint authentifié.
- `functions/test/admin_quote_issue_readiness.test.js` : **13 tests Node** couvrant les blocages, le paiement tiers, les quantités de postes, la tarification publiée, le calcul fiscal au centime et les dates. Ces tests doivent encore être **exécutés** localement ; ils ne représentent pas une validation réglementaire.
- `functions/admin_official_quote_pdf.js` : futur moteur PDF utilisant `pdfkit` déjà installé, les images de marque réutilisées de `sphot_email_design.js` (titre graphique SPHOT sur fond blanc **sans contour**, Fire rouge en bas **sans signature texte**), et toutes les données contrôlées. Il exige un contexte serveur dont les prérequis sont satisfaits **et** un numéro `DV-...` déjà attribué. Il n'écrit pas dans Firestore, ne partage pas de PDF, n'envoie pas d'email et ne crée pas de devis tout seul. C'est la couche de rendu réutilisable, non encore reliée à un parcours d'émission authentifié.
- `lib/web/admin/pages/admin_subscription_panel.dart` : la rubrique 03 conserve **uniquement** « ÉTABLIR UN DEVIS » désactivé, mais son statut est clarifié en « EN ATTENTE D’IMMATRICULATION SPHOT » ; un troisième indicateur orange explicite que le blocage vient de l'émetteur, pas du dossier payeur complet.

**Sécurité et points obligatoires AVANT toute activation** :
1. Immatriculation de SPHOT, identification et statut du représentant légal, et validation du régime fiscal et mentions obligatoires par le professionnel adapté.
2. Service backend authentifié par Firebase Authentication ; contrôler les droits Admin, le rattachement des SPHOTS au territoire, la situation du payeur/tiers, et l'authenticité des vérifications externes. Ne pas accepter des booléens d'authentification/validation envoyés par Flutter.
3. Recalcul de l'offre depuis **la grille publiée** ; jamais depuis le montant d'une saisie client. Décider comment sont conservés les tarifs durant les 30 jours de validité d'un devis.
4. Attribution transactionnelle du numéro via le compteur existant, rendu PDF puis stockage immuable et traçable ; idempotence / reprise en cas d'échec partiel ; aucun devis « émis » tant que le PDF n'est pas présent. Le `DV-...` ne remplace jamais la référence du dossier Admin.
5. Facturation et commandes ne sont pas déclenchées par l'émission d'un devis. Les CGV et leur version publiées restent à raccorder avant les commandes réelles ; règles Chorus Pro et TVA internationales à compléter.
6. Ne pas déployer ni relier le bouton tant que ces conditions ne sont pas levées. Aucun « devis » fictif, aucune simulation alternative, aucun paiement ou abonnement activé.

**Tests recommandés sur le PC de développement** depuis la racine du dépôt, après `git pull` :
`node --test functions/test/admin_quote_validity.test.js functions/test/admin_quote_issue_readiness.test.js`.
`flutter run -d chrome -t lib/main_web_admin.dart` doit montrer le **nouveau statut explicite** et le bouton devis toujours désactivé. Les contrôles de délimiteurs et présence du code ont été réalisés ; compilation Node/PDF réelle et Flutter non exécutées par l'assistant.

## 26. Tests Node validés et test du moteur PDF ajouté (15/10/2026)

**Retour de l'utilisateur depuis Windows PowerShell** :
`node --test functions/test/admin_quote_validity.test.js functions/test/admin_quote_issue_readiness.test.js`
→ **18 tests réussis sur 18 ; 0 échec**, durée rapportée ~179,56 ms. Les cas incluent les validations légales/fiscales et la validité plafonnée à 30 jours dans l'année civile.

**Code ajouté suite au retour :**
- `functions/test/admin_official_quote_pdf.test.js` : 5 nouveaux tests pour le moteur PDF officiel. Rejet si l'émetteur n'est pas immatriculé, si numéro DV absent, si année DV incorrecte, si référence de dossier absente ; production de simples **octets PDF en mémoire** pour un contexte fictif strictement technique, sans créer de fichier commercial, sans envoi ni écriture Firestore.
- Le générateur testé `functions/admin_official_quote_pdf.js` réutilise le titre SPHOT réel et l'image Fire des emails et exige une numérotation DV préalable. **Les cinq tests PDF n'ont pas encore été exécutés par l'utilisateur**. La syntaxe JS a été vérifiée sur les 4 modules de devis/tests ; aucune compilation Flutter ni rendu PDF réel n'a été effectué par l'assistant.
- Confirmation par lecture du code existant `functions/index.js` : `loginAdmin` crée déjà un token Firebase personnalisé avec `adminUid`, `role`, `territoireId`. L'authentification de toute future route d'émission devra exiger **un ID token Firebase vérifié par le serveur**, contrôler le rôle et le territoire **en base**, la situation du compte et les droits; ne pas rétablir ProConnect ni faire confiance à un `adminUid` arbitraire envoyé par Flutter. Le mécanisme `assignQuoteNumberOnWrite` existe déjà, sans émetteur de devis raccordé.

**Test suivant sur PC**, à la racine de SPHOT, après synchronisation de `codex/advertiser-pricing-table-v1` et installation des dépendances `functions` au besoin :
`node --test functions/test/admin_quote_validity.test.js functions/test/admin_quote_issue_readiness.test.js functions/test/admin_official_quote_pdf.test.js`.
Si `pdfkit` manque : `npm --prefix functions install` puis relancer. **Ne pas déployer de nouvelle fonction de facturation à ce stade.**

**Statut non négociable** : bouton « ÉTABLIR UN DEVIS » désactivé, aucun devis numéroté ou archivé réel, aucun paiement ni commande, jusqu'à immatriculation de l'émetteur, fiscalité validée, conformité juridique, endpoint serveur authentifié, numérotation idempotente et conservation immuable du PDF. La validation des tests n'autorise pas le passage en production.

## 27. VALIDÉ SUR PC — test du moteur PDF officiel (15/10/2026)

L'utilisateur a exécuté, après un `git pull --ff-only` réussi :

`node --test functions/test/admin_official_quote_pdf.test.js`

**Résultat : 5/5 tests réussis, aucun échec**, répété une deuxième fois avec succès. Le test confirme la création d'octets PDF en mémoire avec des données fictives, sans émission commerciale ni écriture dans Firestore. Avec les 18 tests de règles/validité déjà réussis : **23 tests réussis** sur les trois fichiers de tests.

La commande `npm --prefix functions install` a ensuite échoué localement avec `ENOENT C:\\Users\\surfS\\sphot\\package.json`. **Aucune installation n'était nécessaire**, puisque `pdfkit` était déjà accessible et les cinq tests PDF avaient réussi avant et après. Si une installation devait devenir nécessaire sur cette machine, ouvrir le sous-dossier `functions` puis `npm install`, et revenir à la racine. Ne pas faire réinstaller l'utilisateur pour ces tests.

**État actuel validé :** les contrôles et le moteur PDF en mémoire sont fonctionnels selon les tests Node. L'affichage réel du PDF, le raccordement du service d'émission authentifié, la numérotation transactionnelle DV, l'archivage immuable et la facturation légale restent non testés / non opérationnels. La section 03 du portail Admin reste bloquée car SPHOT n'est pas immatriculé ; aucun devis réel ni paiement ne doit être créé.

**Étape de développement suivante :** conception ciblée du service d'émission sécurisé qui récupère en serveur l'identité de l'Admin authentifié, son territoire, les postes sélectionnés, la grille publiée, les données de facturation légitimement vérifiées et la configuration émetteur/fiscalité ; blocage par défaut si un élément manque. Ensuite seulement numéro DV transactionnel, PDF officiel et archivage idempotent. Ne pas activer l'émission à partir de tests fictifs.

## 28. Marker Fire unique dans les emails de devis (15/10/2026)

Après validation des aperçus visuels du devis et du mail, l'utilisateur a demandé de corriger uniquement le **Fire rouge en bas de l'email**, qui différait du Fire habituel. **La mise en page générale est validée.**

**Source visuelle officielle vérifiée dans le dépôt :** tous les emails SPHOT communs passent par `functions/sphot_email_design.js`, avec le marker à `cid:sphot-brand-fire-png`, le fichier intégré `fire_red_icon.png` et la taille stable `42 × 65` pixels. Le SVG historique `data/icons/fire_red_icon.svg` reste la source graphique utilisée dans les interfaces/documents qui prennent en charge le vectoriel. Pour l'email, **réutiliser la version PNG embarquée du modèle partagé**, compatible avec les clients mails, est préférable à un SVG incorporé non fiable. Ne pas recadrer une capture ni créer un second marker.

**Code ajouté :**
- `functions/admin_quote_email.js` : générateur d'options Nodemailer pour l'email du DEVIS OFFICIEL (destiné à l'Admin), passant uniquement par `buildSphotMessage`. Celui-ci ajoute automatiquement la véritable image SPHOT dans l'en-tête et un unique Fire officiel en pied, dimensions **42×65**, sans duplication et sans autre variante.
- Vérifications de garde avant préparation de l'email : statut de devis émis et PDF archivé, émetteur et fiscalité vérifiés, numéro `DV-...`, dates/validité sur 30 jours, PDF transmis en pièce jointe et destinataire Admin renseigné. Ces indicateurs doivent être construits par le futur **backend de confiance** à partir d'un enregistrement vérifié, **jamais** reçus comme booléens contrôlés par le navigateur. Le module ne réalise **aucun envoi**, ni écriture Firestore.
- `functions/test/admin_quote_email.test.js` : **6 tests** vérifiant la correspondance exacte des octets du marker embarqué avec le modèle des autres emails, l'unicité du Fire dans le HTML, ses dimensions `42×65`, la pièce jointe DV, le refus de préparer un mail avant émission/archivage, les dates et l'échappement HTML.

**Code existant préservé :** `functions/sphot_email_design.js` et les emails Admin, sauveteur, publicitaire déjà en production ne sont pas modifiés, car leur marker commun est la référence souhaitée. `functions/admin_official_quote_pdf.js` emploie déjà les images issues de `buildSphotMessage` pour le PDF futur ; ne pas changer son habillage visuel sans demande.

**Contrôles effectués :** lecture du vrai header/footer commun SPHOT et de l'implémentation de `buildSphotMessage`, vérification statique de syntaxe JS des deux nouveaux fichiers et de l'absence d'envoi/écritures. **Les 6 nouveaux tests n'ont pas encore été exécutés sur le PC.** Aucun vrai devis, mail, facture ou commande n'a été créé ; le bouton reste bloqué en attente d'immatriculation/fiscalité. Le modèle est un préparateur de message futur, pas un raccordement de production.

**Test à lancer (PowerShell, racine SPHOT, après git pull sur la branche) :**
`node --test functions/test/admin_quote_email.test.js`.
Le résultat attendu est **6 tests réussis** ; ne pas déployer avant validation juridique et backend de génération/archivage.

## 29. Six tests des emails de devis réussis et point de vigilance numérotation (15/10/2026)

**Résultat exécuté par l'utilisateur dans PowerShell** : après mise à jour sur `dfa6061`, commande `node --test functions/test/admin_quote_email.test.js` : **6/6 tests réussis, 0 échec**, durée 238,7313 ms. Les tests contrôlent la correspondance octet par octet du marker Fire avec les autres emails SPHOT, le CID unique à 42 × 65 px, les données et pièce jointe, les blocages d'émission, les dates et la protection contre l'injection HTML. Avec les 18 tests de tarifs/prérequis et les 5 tests PDF déjà passés : **29/29 tests réussis** en cumul de ces suites (exécutées séparément).

**Inspection technique complémentaire** :
- `functions/index.js` contient déjà `assignQuoteNumberOnWrite`, un déclencheur `onDocumentWritten("quotes/{quoteId}")` qui attribue le numéro `DV-...` transactionnellement dès qu'un document `quotes` sans numéro et muni d'une référence Admin reconnaissable existe. **Il ne vérifie pas, à lui seul, la conformité de l'émetteur, de la fiscalité ou la présence d'un PDF archivé.** Il ne faut donc PAS créer des documents `quotes` de prévisualisation ou de brouillon pour tester : cela pourrait consommer des numéros officiels prématurément.
- `functions/admin_workflow.js` contient un registre documentaire `documents` et des PDF Storage utilisés ailleurs ; la rubrique `FACTURES & DOCUMENTS` de `lib/web/admin/pages/admin_dashboard_page.dart` est encore un affichage de préparation, sans consultation réelle des devis.
- **Chemin sûr à construire avant activation** : validation préalable uniquement en lecture ; après identité légale et fiscalité vérifiées, création d'un document de devis officiel avec contrôle serveur authentifié, attribution `DV` via la séquence unique existante et préparation durable du PDF, puis publication dans `documents`/Storage et notification email **après** archivage. Les cas de défaillance partielle devront être idempotents et explicitement récupérables sans écraser un devis historisé. Aucun trigger financier existant ne doit être modifié sans test d'intégration.
- `loginAdmin` crée un jeton Firebase avec UID/role/territoire ; les éventuelles routes de devis devront vérifier le token côté serveur et les droits en base, sans refaire ProConnect. Le modèle d'email de devis est **un préparateur sans envoi**, et le bouton reste volontairement désactivé.

**Aucune modification de déclencheur Firebase, des règles Firestore ou du bouton Admin dans cette étape.** Les 29 tests sont des tests unitaires, pas une émission réelle, une preuve de fiscalité, un rendu email en Outlook ou une intégration complète.

## 30. Préparation de l'archivage officiel des devis — sans émission anticipée (15/10/2026)

**Demande explicite : « archivons »** après validation des 29 tests cumulés (18 règles/validité, 5 PDF, 6 email). Le devis n'est pas encore émissible légalement : SPHOT non immatriculé et fiscalité non configurée. Il est strictement interdit de créer des devis officiels, des PDF contractuels ou des emails à de vrais administrateurs simplement pour tester l'archivage.

**Module serveur interne ajouté** : `functions/admin_official_quote_archive.js`, fonction `archiveOfficialAdminQuote` :
- N'est exporté par AUCUN endpoint Cloud Function : **pas déployé ni déclenché par le portail**. Il doit être appelé exclusivement par un futur orchestrateur authentifié, avec les validations d'identité, de droits, d'émetteur, de fiscalité, de territoires et de grille effectivement réalisées côté serveur.
- Attend un document `quotes/{quoteId}` **déjà numéroté** `DV-{année}-{adhérent}-{séquence}` et en état `numbered_pending_archive`. Vérifie cohérence du document, de la référence `SPHOT-ADM-...`, du contexte serveur et de la validité 30 jours. **Ne crée pas de document quotes ni ne consomme de numéros.**
- Stocke le PDF à chemin stable `adminRequests/{requestId}/documents/financier/{année}/devis/{numeroDV}.pdf`, dans **l'arborescence Storage déjà employée** par les documents administratifs SPHOT. Upload avec précondition GCS `ifGenerationMatch: 0` : refuse l'écrasement de l'objet ; identifiant et empreinte SHA-256 de l'original.
- Écrit dans une transaction Firestore `documents/{requestId}_{numeroDV}` avec `documentType=quote`, `category=financial`, `subcategory=devis`, `status=issued`, références, date, validité, version et référence du tarif publié, nombre de postes, ventilation HT/taxes/TTC, chemin Storage, taille et empreinte du PDF ; **dans la même transaction** marque `quotes/{quoteId}` comme `issued` et `pdfArchived=true`.
- Reprise après incident entre Storage et Firestore : si un PDF identique existe déjà, il compare les octets par SHA-256 et complète uniquement le registre manquant. Si l'original diffère, arrêt sur conflit. Un deuxième appel identique rend `alreadyArchived: true`, sans création d'autre document ni écrasement.
- Aucun `downloadUrl` public n'est émis par l'archiveur ; l'accès authentifié au PDF devra être finalisé lors du développement de la consultation sécurisée et des règles Storage.

**10 tests unitaires Node ajoutés** dans `functions/test/admin_official_quote_archive.test.js` ; ils utilisent exclusivement des imitations de Firestore et Storage en mémoire, sans données réelles. Cas couverts : prérequis serveur, numéro de devis, refus fiscal/juridique, séparation Admin, succès du registre immuable, appel idempotent, impossibilité de remplacer les octets, reprise après transaction interrompue, conflit d'objet existant, état de devis incorrect.

**Portail Admin, lecture seule** : `lib/web/admin/pages/admin_dashboard_page.dart`, rubrique **FACTURES & DOCUMENTS → DEVIS** : remplacement du bloc statique par un `StreamBuilder` filtrant `documents` sur l'UID Admin connecté, puis `documentType=quote`, `status=issued` et présence du chemin Storage. Affiche les références et dates de vrais devis archivés ou **AUCUN DEVIS ÉMIS** si liste vide. Aucun faux devis ou PDF de simulation n'est créé, aucune action d'émission ou de téléchargement sensible n'est activée. Si les règles Firestore interdisent la lecture, indique **ARCHIVES INDISPONIBLES** : **les droits de lecture Firestore/Storage devront être vérifiés avant exploitation**.

**Contrôles effectués côté assistant** : lecture du registre `documents` existant, du mécanisme de numérotation DV déjà en place, du bandeau Admin et des conventions de stockage ; vérification de la syntaxe JavaScript et de la présence des protections. **Les dix tests Node et la compilation Flutter restent à exécuter sur le PC utilisateur.**

**Commandes de test PowerShell, à la racine SPHOT, sans aucun déploiement Firebase :**
```powershell
git pull --ff-only origin codex/advertiser-pricing-table-v1
node --test functions/test/admin_official_quote_archive.test.js
flutter run -d chrome -t lib/main_web_admin.dart
```
Dans FACTURES & DOCUMENTS, aucune entrée DV ne doit être inventée. Le texte visible pourra indiquer « AUCUN DEVIS ÉMIS » ou, si l'accès Firestore n'est pas autorisé, « ARCHIVES INDISPONIBLES ». Un numéro DV ne doit être attribué que par la procédure officielle future, après finalisation juridique et fiscale.

**Travail à faire avant exploitation** : endpoint serveur authentifié et idempotent d'émission (non présent), vérification réelle des droits Admin et d'un payeur tiers, contrôle du tarif publié et fiscalité, alignement avec le trigger `assignQuoteNumberOnWrite`, test en émulateur Firebase du stockage + transactions/reprise, sécurisation des règles Firestore et Storage, accès au PDF pour le bon Admin, traçabilité de l'envoi email après PDF effectivement archivé. Pas d'activation du bouton DEVIS ni de paiement.

## 30. Préparation de l'archivage des devis officiels (15/10/2026)

Demande utilisateur : **« archivons »**. Un module d'archivage des futurs devis **déjà émis et juridiquement autorisés** a été ajouté **sans déploiement, sans écriture dans la base réelle et sans génération de numéros**.

- `functions/admin_quote_archive.js` : préparation d'une référence déterministe `adminRequests/{requestId}/documents/financier/{année}/devis/{DV}.pdf` et d'une entrée du registre documentaire existant `documents/{requestId}_{DV}`. Contrôles : numéro de devis lié au membre administratif, année d'émission, PDF commençant par `%PDF-`, statut `issued`, contrôle d'un contexte d'autorisation exclusivement construit par le futur backend de confiance. Conservation du hash SHA-256 du PDF et interdiction de remplacement. Téléversement Storage avec précondition `ifGenerationMatch:0`, reprise idempotente après stockage réussi/registre non inscrit, écriture exclusive `registryRef.create`. Aucun email envoyé, aucun numéro attribué, aucun devis créé.
- `functions/test/admin_quote_archive.test.js` : 8 nouveaux tests utilisant uniquement de faux objets Firestore/Storage en mémoire : préparation, refus si émetteur non vérifié, refus de brouillon, archivage une seule fois, protection contre la modification du PDF, reprise après échec partiel, conflits dans Storage et dans le registre.
- La présentation du registre pour `FACTURES & DOCUMENTS` reste à raccorder (lecture des documents existants filtrée par droits du vrai Admin, téléchargement sécurisé). **Ne pas afficher un faux état « devis émis » avant que PDF et registre concordent**.
- **Important** : le verrou `trustedServerGate` est un argument d'API interne, PAS une preuve suffisante si un navigateur pouvait le transmettre ; le futur endpoint authentifié devra calculer cette valeur côté serveur après vérification de Firebase Authentication, des droits, de l'émetteur et de la fiscalité. En l'absence de ce branchement, le module reste **inaccessible depuis Flutter**. La numérotation `DV` existante dans `functions/index.js` est inchangée.
- **Tests statiques JS vérifiés**, mais nouveaux 8 tests Node **à exécuter sur le PC de développement** :
  `node --test functions/test/admin_quote_archive.test.js`.
- Le cumul antérieur est de **29 tests réussis** ; les 8 nouveaux ne sont pas encore validés en exécution. Pas de mise en production ni émission réelle avant immatriculation SPHOT et validations juridiques, fiscales et sécurité serveur.
