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
