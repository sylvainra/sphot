# SPHOT — Cartographie des accès Firestore et plan de tests (15/10/2026)

**Statut : AUDIT ET STRATÉGIE, AUCUNE RÈGLE À DÉPLOYER.**
Référence de travail : branche \`codex/advertiser-pricing-table-v1\`, commit \`df2cc2f\`.
Règles courantes : celles communiquées par l'utilisateur le 15/10/2026, avec le bloc \`documents\` ajouté et validé dans Firebase Console. Le dépôt \`firebase.json\` ne déclare aucun fichier \`firestore.rules\` actif. Le contenu effectif du projet Firebase n'a pas été relu par API dans cet audit.

## Objectif métier

L'Admin d'une collectivité doit continuer à s'inscrire, gérer ses SPHOTS, préparer un abonnement et retrouver ses documents ; il ne doit pas pouvoir se donner un rôle supérieur, approuver son dossier, changer un tarif officiel ou émettre un devis. Le Super Admin doit conserver l'instruction administrative, la grille tarifaire et les validations par des opérations serveur authentifiées. Les sauveteurs et annonceurs doivent conserver uniquement leurs usages autorisés.

**Seules les décisions d'accès sont étudiées ici.** Aucun prix, document officiel, compte, paiement, période d'essai, interface ou Firestore de production n'est modifié.

## 1. Cartographie des données et flux prouvés dans le code

| Collection / objet | Usage visible | Accès client actuel selon règles fournies | Cible recommandée | Prérequis avant changement |
|---|---|---|---|---|
| \`publicSpots/{id}\` | Lecture publique de la carte | Lecture publique, écriture refusée | Identique ; alimentation serveur | Vérifier les consommateurs mobile/Web |
| \`adminRequests/{id}\` | Inscription initiale, correction, instruction, historique, accusés | Toute lecture et écriture permises | Consultation limitée ; création/correction protégées ; statuts et décisions serveur | Migrer l'inscription initiale et la correction authentifiée par jeton temporaire |
| \`admins/{uid}\` | Territoire, rôle et droits approuvés | Toute lecture et écriture permises | Lecture propre au compte ; rôle/droits modifiés côté serveur | Identifier les mises à jour légitimes du profil et du logo |
| \`adminAccounts/{login}\` | Compte de connexion et association uid/territoire | Refus client par défaut (pas de match) | Serveur uniquement | Auditer le stockage et la vérification des mots de passe |
| \`subscriptions/{uid}\` | Organisme payeur, sélection des postes, offre, préférence de paiement, statut commercial | Toute lecture et écriture permises | Lecture du titulaire ; saisie limitée aux champs préparatoires ; prix et statuts serveur | Séparer champs modifiables et champs de confiance ou utiliser des règles de champs rigoureuses |
| \`territoires/{id}/spots/{spotId}\` et autres sous-collections | Création SPHOT, sauveteurs, planning et surveillance | Toute lecture et écriture permises par correspondance récursive | Lecture selon type de donnée ; écriture authentifiée limitée au territoire et à la fonction | Inventaire spécifique Web/mobile/sauveteur, sans interrompre la sécurité opérationnelle |
| \`spots\`, \`periodesSurveillance\`, \`sauveteurs\` (racines) | Données métier historiques | Toute lecture et écriture permises | À distinguer des données publiques ou protégées ; migration graduelle | Recenser les anciens consommateurs |
| \`commercialPricingMarkets\` | Grille publiée et versionnée, modification Super Admin côté serveur | Pas de règle cliente explicite | Reste réservé au serveur ; aperçu public seulement via endpoint contrôlé | Aucun accès Firestore direct à ouvrir |
| \`quotes\`, \`quoteIssueAuthorizations\`, \`counters\` | Devis, preuve de numérotation et compteurs | Pas de règle cliente explicite | Serveur uniquement, accès client refusé | Conserver ce verrou lors de l'orchestration |
| \`documents/{id}\` | Registre des devis émis, documents administratifs | Règle ciblée : lecture par \`adminUid\`, écriture client refusée | Conserver ; étudier l'accès Super Admin via serveur | Tester lecture propre, rejet d'accès croisé et requête Firestore filtrée |
| \`legalDocuments\`, \`legalVersions\` | Publication et versionnement des textes juridiques | Toute lecture et écriture permises | Lecture publique des versions publiées ; écriture Super Admin côté serveur | Préserver la consultation avant inscription et le versionnement |
| \`adRequests\`, \`advertiserRequests\`, \`advertiserAccounts\` | Parcours publicitaires et comptes | Toute lecture et écriture permises | Vérification séparée : demandes et comptes sensibles | Ne pas casser l'inscription et les campagnes annonceurs |
| \`communes\`, \`settings\`, \`test\` | Données diverses | Toute lecture et écriture permises | Inventaire et restriction progressive | Identifier les fonctionnalités et tests existants |

### Preuves de dépendance (branche auditée)

- \`lib/web/admin/pages/admin_trial_request_page.dart\` : \`_saveRegistration\` aux environs des lignes 1164–1420 crée \`adminRequests\` directement depuis Flutter, parfois avec un nouvel identifiant généré, et \`_loadExistingRequest\` autour de la ligne 251 consulte une demande en correction.
- \`lib/web/admin/pages/admin_subscription_panel.dart\` : \`_subscriptionReference\` ligne 169 ; \`_saveSection\` lignes 446–472 écrit directement dans \`subscriptions/{adminUid}\` les champs payeur, choix des postes et préférences. \`territoires/{territoireId}/spots\` est lu dans l'étape d'offre autour de la ligne 931.
- \`lib/web/admin/pages/admin_dashboard_page.dart\` : listes globales \`adminRequests\`, \`subscriptions\`, \`adRequests\`, \`sauveteurs\` lignes 529–541 ; mises à jour directes de documents \`admins\`, \`adminRequests\`, \`territoires\` et sous-collections ; actions \`_approveAdminRequest\`/\`_rejectAdminRequest\` autour des lignes 12095–12250 ; publications juridiques directes autour de 13455–13650.
- \`lib/map/profil_login_page.dart\` : après \`loginAdmin\`, \`signInWithCustomToken\` vers la ligne 466 ; chemin Super Admin distinct vers \`/super-admin\` autour de 546–565.
- \`functions/index.js\` : \`loginAdmin\` à partir de la ligne 8215 valide le compte de \`adminAccounts\`, compare actuellement le mot de passe fourni au champ \`temporaryPassword\`, puis crée un Custom Token Firebase avec \`adminUid\`, \`role\` et \`territoireId\` vers la ligne 8771. Le Super Admin utilise par ailleurs une session Web temporaire, et la grille tarifaire dispose d'une API serveur dédiée.
- \`functions/admin_quote_orchestrator.js\` : contrôle préalable interne sans droits d'émission ; adaptateurs de confiance encore à créer. Ne pas interpréter les champs de souscriptions ou de demande comme des attestations légales.

## 2. Risques observés et frontières de confiance

**Critique — autorisations publiques** : les règles Firestore actuellement partagées comportent \`allow read, write: if true\` pour des collections sensibles. Un utilisateur sans session peut, en théorie, modifier des rôles, statuts commerciaux, identité du payeur ou informations opérationnelles en écrivant directement via le SDK/API. Cela ne démontre pas qu'un abus a eu lieu.

**Critique — recouvrement des règles** : \`match /territoires/{territoireId}/{document=**}\` autorise toutes les sous-collections par héritage du motif récursif. Ajouter une règle restrictive plus spécifique à \`spots\` sans enlever ou modifier cette autorisation ne suffit PAS : Firestore autorise si au moins une règle correspondante renvoie vrai.

**Important — flux avant connexion** : \`adminRequests\` doit actuellement accepter des créations et corrections depuis Flutter avant la session Admin définitive. Il faut prévoir un endpoint serveur protégeant l'identité et les autorisations, notamment les jetons de correction, avant de fermer l'accès direct.

**Important — session Super Admin distincte** : un jeton de session Web propre au Super Admin n'est pas automatiquement une identité \`request.auth\` de Firestore. Les approbations et publications effectuées directement depuis Flutter doivent migrer vers des opérations serveur vérifiant cette session, et non être simplement autorisées par une revendication de rôle déclarée dans le navigateur.

**Important — source non fiable pour le devis** : l'Admin peut saisir/modifier les coordonnées payeur et les postes dans \`subscriptions\`. Ces valeurs sont des propositions, pas des vérifications légales ou fiscales. Les critères de numérotation, de TVA, de prix publié et de droits d'accès doivent être établis sur des sources serveur protégées.

**Important — mot de passe** : \`loginAdmin\` compare directement \`temporaryPassword\` à la chaîne envoyée par le client. Audit séparé requis pour le stockage, la rotation et une migration éventuelle vers un système de mots de passe hachés/Firebase Auth. Ne pas entreprendre une conversion sans protocole évitant de bloquer les comptes actuels.

**Point conservé** : \`documents\` est consultable par l'Admin propriétaire via la règle corrigée ; \`quotes\`, \`quoteIssueAuthorizations\` et \`counters\` n'ont pas d'autorisation cliente explicite dans les règles fournies. Le SDK Admin côté serveur contourne les règles Firestore ; la sécurité des Cloud Functions doit donc être vérifiée indépendamment.

## 3. Contrat de sécurité et matrice de tests À EXÉCUTER

La matrice ci-dessous décrit les attentes du **futur modèle**, et NON le comportement sécurisé du projet actuel. Les tests négatifs sur \`admins\`, \`subscriptions\` et \`adminRequests\` échoueraient avec les règles ouvertes actuelles : c'est précisément ce qu'il faudra corriger.

| ID | Profil / scénario | Attendu |
|---|---|---|
| S01 | Visiteur : lire \`publicSpots\` | AUTORISER |
| S02 | Visiteur : écrire \`publicSpots\` | REFUSER |
| S03 | Visiteur : lire ou modifier \`admins\` | REFUSER |
| S04 | Visiteur : lister \`adminRequests\` ou \`subscriptions\` | REFUSER |
| S05 | Nouveau demandeur : créer un dossier via le futur flux serveur autorisé | AUTORISER, après contrôles d'identité et format |
| S06 | Demandeur : modifier sa demande à l'aide d'un jeton de correction invalide/expiré | REFUSER |
| S07 | Admin authentifié : lire son propre dossier et son abonnement | AUTORISER |
| S08 | Admin A : lire ou modifier le dossier/l'abonnement de l'Admin B | REFUSER |
| S09 | Admin : s'attribuer un rôle ou un accès \`approved\` | REFUSER |
| S10 | Admin : modifier son formulaire de payeur et sa sélection de postes autorisée | AUTORISER, avec contrôles des seuls champs éditables |
| S11 | Admin : modifier directement \`subscriptions.status\`, montant officiel, taxe ou date de facture | REFUSER |
| S12 | Admin : consulter les SPHOTS de son territoire dans le cadre de son accès | AUTORISER |
| S13 | Admin A : modifier le territoire de l'Admin B | REFUSER |
| S14 | Sauveteur : effectuer une opération permise sur son poste via le circuit autorisé | AUTORISER |
| S15 | Sauveteur : modifier un autre territoire ou les droits d'Admin | REFUSER |
| S16 | Admin : lire les \`documents\` dont \`adminUid == request.auth.uid\` | AUTORISER |
| S17 | Admin A : consulter le document archivé de l'Admin B | REFUSER |
| S18 | Client quelconque : créer ou remplacer un PDF archivé / écrire \`documents\` | REFUSER |
| S19 | Client quelconque : créer un DV, écrire un compteur ou une autorisation \`quoteIssueAuthorizations\` | REFUSER |
| S20 | Visiteur : lire les textes juridiques publiés | AUTORISER |
| S21 | Client quelconque : modifier \`legalDocuments\` ou \`legalVersions\` | REFUSER |
| S22 | Super Admin : décider une approbation via une opération serveur avec session valide | AUTORISER |
| S23 | Même requête Super Admin avec session expirée ou falsifiée | REFUSER |
| S24 | Lecteur public : appeler l'aperçu de tarif publié, sans modifier la grille | AUTORISER la lecture publiée seulement |
| S25 | Admin A : requête Firestore non filtrée listant les documents de tous les Admins | REFUSER |
| S26 | Un compte annonceur : écrire les droits ou abonnements d'un Admin | REFUSER |

### Critères de non-régression indispensables

- Inscription initiale, demandes de correction et suivi de dossier toujours fonctionnels.
- Connexion Admin et Super Admin, demande et validation administratives, et renouvellement de sessions toujours fonctionnels.
- Création/édition des SPHOTS, planning, sauveteurs, changements d'affectations, périodes de surveillance et sécurité opérationnelle préservés.
- Saisie de l'abonnement et du payeur conservée, mais décisions/valeurs financières officielles non modifiables directement par le navigateur.
- \`FACTURES & DOCUMENTS\` : lecture propre à l'Admin et refus des lectures croisées, sans suppression de documents.
- Les conditions juridiques, tarifs et versions des CGU/CGV restent contrôlés ; les documents existants sont historisés.
- Aucun devis émis, numéro DV consommé, facture créée, paiement prélevé ou email réel déclenché pendant les tests.

## 4. Ordre de sécurisation proposé (avec points de contrôle)

**Phase A — sans modification de l'application** : récupérer/exporter la version exacte des règles actuellement publiées et la conserver hors production ; préparer un jeu de données anonymisées de test ; mettre en place Firebase Emulator Suite et un exécuteur de tests des règles (\`@firebase/rules-unit-testing\`, non encore installé). Les tests d'émulateur devront manipuler uniquement le projet local \`demo-*\` et des identités fictives.

**Phase B — architecture sans activation** : définir un flux serveur pour création/correction \`adminRequests\`, mutations administratives Super Admin et champs commerciaux de confiance ; identifier les fonctions déjà présentes pour éviter les doublons. Préparer un fichier de règles CANDIDAT non référencé par \`firebase.json\`. Tester S01–S26 en émulateur. Prévoir des scénarios Firestore \`list\` avec filtres conformes aux règles ; les règles ne sont pas des filtres automatiques.

**Phase C — passage progressif des clients** : migrer par domaine les écritures directes vers des endpoints contrôlés, tester les interfaces Web/mobile/sauveteur et les données de non-régression ; distinguer brouillons modifiables et preuves serveur immuables. Ne jamais resserrer une collection nécessaire aux parcours existants avant la migration correspondante.

**Phase D — activation sur décision explicite** : audit et sauvegarde des règles publiées, examen du diff exact, plan de retour arrière, vérification des contrôles en émulateur, puis validation expresse de l'utilisateur avant toute publication Firebase. Aucun déploiement implicite depuis ce document.

## 5. État vérifié ce jour

- Audit de lecture du code GitHub et des règles transmises : effectué.
- Cartographie des opérations sensibles et scénarios S01–S26 : rédigés.
- Installation de Firebase Emulator / exécution des tests S01–S26 : **non réalisée**.
- Écriture des nouvelles règles candidates : **non réalisée**.
- Changement d'interface, Cloud Function, collection ou règle Firebase : **aucun**.

**Décision attendue avant la phase B** : confirmer que nous pouvons préparer un prototype de règles et une suite de tests en émulateur, toujours sans modifier les règles publiées et sans activer l'émission des devis.
