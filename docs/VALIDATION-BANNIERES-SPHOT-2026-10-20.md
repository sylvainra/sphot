# SPHOT — Référence validée des affichages publicitaires (20/10/2026)

## État visuel accepté

Captures de contrôle utilisateur du 20 octobre 2026 : carte Web sans volet, carte Web avec volet ouvert (LONGE 06 et LONGE 09), version mobile et encarts des fiches SPHOT. L'utilisateur confirme que les interactions et visuels sont satisfaisants.

Conserver ces dimensions et placements lors des modifications futures, sans modifier la carte ni les six rubriques opérationnelles.

- Carte Web : bandeau compact, hauteur plafonnée à 118 px, placé au-dessus du menu inférieur ; la hauteur tient compte de la largeur disponible et du volet latéral.
- Carte mobile : bandeau compact, zone d'invitation limitée à 46 px de largeur.
- Zone distincte sur la carte : Fire rouge SVG `data/icons/fire_red_icon.svg` au-dessus du texte exact **Votre SPHOT PUBLICITAIRE ici!**, ouvrant le parcours annonceur. Clic sur l'image : destination approuvée de l'annonceur.
- Fiches SPHOT : conserver les encarts publicitaires et l'accès à la création déjà testés sur Web et mobile.

## Visuels des campagnes

Le formulaire `lib/web/advertiser/widgets/advertising_spot_section.dart` vérifie pour chaque nouvel import un JPEG/PNG/WEBP, une taille maximale de `2 * 1024 * 1024` octets et une résolution exacte de **1800 x 300 px**.

Le visuel Surf Shop Atlantique fourni en test mesure 1800 x 300 px, 346301 octets (source transmise le 20/10/2026). Le fichier transmis ne doit pas être embarqué en dur dans le code de production.

Sur la carte, `lib/map/map_page.dart` lit l'URL de campagne `bannerUrl`, identique pour Web et mobile ; `webBannerUrl` n'est qu'un recours pour les anciens enregistrements sans `bannerUrl`. Plus aucune exception liée à un identifiant de démonstration n'est nécessaire.

**Limite d'affichage** : le mode Web compact utilise `BoxFit.fill` pour rendre l'image entière sans recadrage, au prix d'une modification des proportions de l'image source. Ne pas affirmer que les proportions originales sont préservées ; un éventuel changement serait à faire valider séparément.

Les URL historiques déjà enregistrées ne prouvent pas à elles seules leur conformité : l'import initial contrôle les nouveaux fichiers, mais une URL rechargée peut être considérée comme valide en l'absence des métadonnées. Ajouter un contrôle serveur avant toute nouvelle garantie contractuelle universelle.

## Aperçu commercial — validé visuellement (20/10/2026)

Le fichier `lib/web/advertiser/widgets/diffusion_central_preview.dart` affiche les octets du visuel chargé à l'étape 2 ou son URL enregistrée. La maquette Carte reproduit un bandeau mobile compact avec une zone distincte (Fire rouge + texte exact) à droite. La maquette Fiches reproduit le bandeau 6:1 et son bouton distinct en dessous. Les six onglets et l'agrandissement restent en place. **Validation explicite utilisateur : capture de l'étape 3 « DIFFUSION » du 20/10/2026, rendu jugé « entièrement satisfaisant » et confirmé/validé pour enregistrement et publication.** Le même visuel importé est utilisé dans les deux aperçus ; aucune image Surf Shop Atlantique n'est codée en dur. Aucun changement supplémentaire de géométrie autorisé sans une nouvelle validation.

Objectifs à vérifier lors des essais :
- reproduire le même visuel que celui effectivement soumis pour la campagne ;
- montrer les bonnes dimensions visuelles des emplacements Carte et Fiches dans les maquettes, Web et mobile ;
- inclure explicitement la zone attenante **Votre SPHOT PUBLICITAIRE ici!** et son Fire rouge dans l'aperçu Carte, pour éviter toute surprise après achat ;
- prévisualiser les éventuelles déformations dues au format compact, sans recadrer ni cacher de texte ;
- soumettre les adaptations d'interface à validation avant modification structurelle.

## Livraison de l'étape 3 et retrait futur du test

- Référence fonctionnelle validée avant ce constat : `095601dabb32ee02ee83e430a61b118b9df8a477` (code de l'aperçu et note en attente de validation).
- La validation visuelle est confirmée le 20/10/2026 ; il faut encore synchroniser le PC, analyser le fichier modifié, reconstruire `build/web` et publier cette nouvelle compilation sur Firebase Hosting `sphot-ab80b`. Ne pas confondre le précédent déploiement réussi de la carte avec ce nouveau déploiement de l'étape 3.
- La campagne démonstrateur « Surf Shop Atlantique » est destinée à être retirée **dans une opération Firestore séparée** après identification de sa référence exacte et contrôle des éventuels liens ; ne supprimer ni une campagne réelle, ni le site Hosting `sphot-advertiser-test`, ni les éléments partagés sans inventaire.

## Notification d'approbation du changement de visuel — validée

- Le 20/10/2026, l'utilisateur a validé visuellement l'email « PROPOSITION À APPROUVER », bouton d'accès bleu opérationnel après le déploiement ciblé de `sendAdvertiserAssetChangeEmail`.
- L'email « MODIFICATION APPROUVÉE » était absent lors d'une approbation suivante, alors que le Super Admin affichait le statut approuvé.
- Cause de code corrigée : la notification ne repose plus uniquement sur un changement de `assetChangeRequest.syncStatus`, qui peut rester `applied` entre deux propositions. Elle se déclenche à la mise à jour de `lastSyncAt` pour une proposition approuvée, après la synchronisation, et garde une clé d'envoi stable par proposition (`submittedAt`) pour les reprises Firebase.
- Modules concernés : `functions/index.js`, `functions/advertiser_asset_change_email_trigger.js` et son fichier de tests `functions/test/advertiser_asset_change_email_trigger.test.js`. Aucun changement aux textes, au bouton HTML, à la carte, aux tarifs ou aux données Firestore.
- L'utilisateur a confirmé le 20/10/2026 que les deux emails arrivent et sont fonctionnels après le déploiement Firebase réussi de `sendAdvertiserAssetChangeEmail` et la création de `syncApprovedAdvertiserAssets` en `europe-west1`. Le déploiement a passé ESLint. Les anciennes décisions ne génèrent pas rétroactivement un message.

## Nettoyage / suivi du déploiement

Suppressions du dépôt : cache local `.firebase/hosting.YnVpbGRcd2Vi.cache`, fichier de configuration d'émulateur publicitaire isolé, règles d'émulateur dédiées, deux scripts d'essai local isolé et ancien mode d'emploi associé. `.firebase/` est ignoré par Git ; les tests unitaires utiles à la projection publique sont conservés dans `functions/test/`.

Ne pas confondre suppression de fichiers de test versionnés et suppression d'un site Firebase, d'un projet Firebase, de Firestore ou de Storage : aucune donnée distante ne doit être détruite sans inventaire et validation explicite.

Le commit GitHub et la validation des captures ne constituent **pas** un déploiement Firebase Hosting. Procédure de déploiement à effectuer sur le PC après synchronisation de `main` : vérification Flutter, build Web de production, puis `firebase deploy --only hosting --project sphot-ab80b`, avec confirmation du site cible. Ne pas déployer les Cloud Functions pour cet ajustement UI.

## Validation Super Admin — 20/10/2026

- Utilisateur : les emails annonceur « PROPOSITION À APPROUVER » et « MODIFICATION APPROUVÉE » sont reçus et fonctionnels après déploiement des deux fonctions `sendAdvertiserAssetChangeEmail` et `syncApprovedAdvertiserAssets`.
- Interface comparative avant approbation expressément validée : deux visuels « AVANT » / « APRÈS » agrandissables, deux positions et leur distance sur une carte à deux repères ; mention explicite si un élément reste inchangé.
- Implémentation sur `main` dans `lib/web/super_admin/widgets/advertiser_asset_comparison.dart` et `lib/web/super_admin/pages/super_admin_dashboard_page.dart`. L'interface n'est affichée qu'avec une proposition `assetChangeRequest.status == submitted`.
- Lors de **chaque décision sur une proposition soumise** (approbation, refus, demande d'ajustements), conservation dans `advertiserRequests/{id}.assetChangeHistory` par `FieldValue.arrayUnion` de la décision, du motif, de la date, des URL des visuels et des positions avant/après. Historique consultable dans le volet Super Admin par « CONSULTER AVANT / APRÈS ». L'écriture se fait dans le document du dossier déjà utilisé par l'interface ; aucune sous-collection supplémentaire n'est requise. Les données antérieures à cette fonctionnalité ne sont pas reconstituées artificiellement.
- Le circuit emails, les offres commerciales, la carte publique et les fonctions Cloud ne sont pas modifiés par ce lot comparatif.
- **À vérifier sur le PC avant publication** : `flutter analyze` ciblé sur le nouveau widget et le dashboard, `flutter build web --release -t lib/main.dart`, puis `firebase deploy --only hosting --project sphot-ab80b`. Vérifier la comparaison sur une nouvelle proposition avant toute approbation réelle et l'historique après une décision. Ne pas déclarer la publication effective avant preuve du terminal.


## Consolidation finale avant publication Web — 20/10/2026

- Référence de départ `main` confirmée sur le PC : `e1d0016`, état de travail propre avant ce lot.
- Une seule présentation de comparaison conservée : `advertiser_asset_comparison.dart`. Le composant concurrent inutilisé a été retiré.
- La carte comparative cadre les deux positions, distingue bleu/vert et indique les éléments inchangés uniquement lorsque les valeurs réelles sont disponibles.
- Agrandissement d'un visuel ancien ou nouveau sous un titre neutre.
- Aucune modification supplémentaire des fonctions Firebase déjà validées ; **publication Hosting à effectuer depuis le PC**, pas depuis ce document.

## Ajustement des aperçus visuels — 20/10/2026

- Retour du test Chrome sur `main` : la comparaison des positions et la carte sont validées par l'utilisateur ; seuls les aperçus des deux visuels réclament un ajustement.
- Les deux visuels sont désormais affichés l'un sous l'autre, chacun sur toute la largeur disponible, avec son bouton d'agrandissement.
- La vue comparative utilise `WebHtmlElementStrategy.prefer`, comme la fenêtre d'agrandissement dont l'affichage est confirmé, afin de remédier au message « Visuel inaccessible ».
- Un seul fichier Flutter modifié : `lib/web/super_admin/widgets/advertiser_asset_comparison.dart`. Pas de changement des positions, décisions, emails, synchronisations ni données Firestore.
- Commit du correctif : `904a4d4`. Compilation Flutter, test Chrome et publication Hosting à confirmer sur le PC avant de les marquer validés.

## Rayon et CGV publicitaires — 20/10/2026

Décisions explicites de l'utilisateur :
- Une modification de rayon/zone, vers un rayon plus grand ou plus petit, ne peut être approuvée avant l'expiration de la période payée en cours.
- Visuel et position restent approuvables séparément, sans attendre la fin de période, même en cas de demande mixte.
- Après l'échéance, le nouveau rayon nécessite une nouvelle tarification, une acceptation commerciale et un paiement. Pas de prorata/révision rétroactive.
- Les CGV propres au SPHOT PUBLICITAIRE doivent figurer distinctement avec CGU, confidentialité et RGPD ; acceptation et version traçables.
- Adapter les emails de réception et d'approbation, l'interface annonceur et le Super Admin.

Implémentation conservatrice sur `main` :
- `assetChangeRequest` garde la proposition de visuel/position.
- `radiusChangeRequest` reçoit séparément `previousTerritory`, `proposedTerritory`, `status: waiting_period_end`, `submittedAt`, `priceAcknowledged`, `noticeVersion`, `cgvVersionAccepted` et `acceptedAt`. Aucune écriture immédiate de `advertisingTerritory` ni de `adRequests.radiusKm`.
- Super Admin : comparaison avant/après du rayon, consultation des fins de campagne liées au dossier par `advertiserRequestId`, bouton d'autorisation désactivé tant que la dernière échéance n'est pas échue ou vérifiable. Le contrôle est refait avant l'écriture. À l'échéance, état `approved_pending_payment` : **accord administratif pour une prochaine souscription, sans activation géographique**.
- E-mails : même fonction `sendAdvertiserAssetChangeEmail` avec textes adaptés, une notification pour une demande mixte, et messages dédiés pour les transitions de rayon en attente puis en attente de paiement. Pas de prétention d'activation anticipée.
- CGV spécifiques : contenu initial version 1.0 dans `advertiser_cgv_policy.dart`, document Firestore optionnel `legalDocuments/advertiserCgv` dans l'éditeur Super Admin ; publication et versions successives archivées dans le document, sans toucher aux versions communes. L'inscription annonceur accepte les CGV séparément et enregistre leur version. Les demandeurs déjà approuvés reconnaissent l'article spécifique au moment d'une proposition de rayon.
- La clause approuvée couvre **le changement de rayon** ; une révision juridique des autres clauses commerciales générales reste nécessaire avant de présenter cet ensemble comme des CGV complètes.

**Limite commerciale volontaire** : aucun changement de zone dans une campagne active, et aucune activation automatique du nouveau rayon avant raccordement aux nouveaux devis/paiements de la période suivante (Odoo/Stripe). `approved_pending_payment` n'est donc PAS un état « diffusé ». Prévoir ce raccordement et des tests de non-régression avant la mise en exploitation des renouvellements.

**Vérifications à réaliser sur le PC avant tout déploiement** :
```powershell
git pull --ff-only origin main
node --test functions/test/advertiser_radius_change_email_trigger.test.js
node --test functions/test/advertiser_asset_change_email_trigger.test.js
node --test functions/test/advertiser_campaign_sync.test.js
npm --prefix functions run lint
flutter analyze lib/web/advertiser/widgets/advertising_spot_section.dart lib/web/advertiser/widgets/advertiser_legal_acceptance_section.dart lib/web/super_admin/pages/super_admin_dashboard_page.dart lib/web/super_admin/widgets/advertiser_asset_comparison.dart lib/web/super_admin/widgets/super_admin_advertiser_cgv_editor.dart
flutter build web --release -t lib/main.dart
```
Publier ensuite **uniquement si les tests sont réussis** : Hosting et la seule fonction d'email modifiée `sendAdvertiserAssetChangeEmail`. Ne pas redéployer `syncApprovedAdvertiserAssets` (inchangée).

## Correction des essais de rayon — 20/10/2026

**Signalement utilisateur après essai Chrome :**
- Les emails « PROPOSITION À APPROUVER » et « MODIFICATION APPROUVÉE » portent encore l'ancien texte : `sendAdvertiserAssetChangeEmail` est mis à jour sur `main` mais la Cloud Function en production n'a PAS encore été redéployée.
- La carte du dashboard annonceur suivait la sélection locale du rayon, même si celui-ci n'était pas approuvé ou était refusé. Ce n'est pas une preuve de modification de `adRequests`.
- L'ancienne interface Super Admin ne permettait pas un refus **distinct** du rayon.
- Certaines demandes historiques contiennent `assetChangeRequest.proposedTerritory` plutôt que `radiusChangeRequest.proposedTerritory`.

**Corrections enregistrées sur `main` :**
- La carte affiche exclusivement la zone contractuelle `advertiserRequests.advertisingTerritory` et la localisation approuvée; une proposition de position est représentée séparément en bleu. Une sélection de rayon non validée n'agrandit jamais le cercle rouge actif.
- Après une proposition de rayon, la sélection revient au contrat actif. Formulaire bloqué pour une seconde modification de rayon tant que la première est en attente.
- Écoute du statut de la demande de rayon depuis les instantanés Firestore jusqu'au refus, sans nécessiter de rouvrir la page. Vérification du rayon contractuel avant la nouvelle soumission.
- Le Super Admin possède un bouton indépendant `REFUSER LE CHANGEMENT DE RAYON`, avec motif et historisation ; aucune mise à jour de `advertisingTerritory` ou de `adRequests.radiusKm`.
- La comparaison Super Admin affiche aussi les anciens `assetChangeRequest.proposedTerritory` pour information, mais ne les transforme **pas** en approbation du rayon (nouvelle soumission et acceptation tarifaire nécessaires).
- Les emails comprennent la demande, l'approbation d'actifs, l'accord conditionné au paiement et le **refus explicite du rayon**. Le circuit Node conserve ses protections contre les doubles envois.

**Validation restante obligatoire :** tests Node, lint, analyse et build Flutter local, essais Chrome (nouvelle demande de rayon, refus, autre demande, demande mixte). Puis déploiement ciblé `functions:sendAdvertiserAssetChangeEmail` et vérification des nouveaux mails, et Hosting uniquement après confirmation UI. Ne pas considérer les emails en production à jour avant ce déploiement.

**Attention aux données de test héritées :** si `advertisingTerritory` ou `adRequests.radiusKm` ont déjà été écrasés par une ancienne version, aucune migration/correction automatique des données de production n'est autorisée ici ; vérifier les documents et l'historique avant correction manuelle ciblée.

## Décisions définitives et organisation Super Admin — 20/10/2026

Décision de simplification validée par l'utilisateur :
- Modification de **visuel** et/ou **position** : circuit Super Admin existant conservé, comparateur avant/après, trois boutons actuels, emails historiques « PROPOSITION À APPROUVER » et « MODIFICATION APPROUVÉE » conservés sans nouveau texte.
- **Rayon / zone de diffusion** : fixé pendant la période publicitaire payée, aucune demande de rayon ni notification ni approbation/refus Super Admin. Le choix d'un autre rayon relève uniquement d'une **nouvelle souscription après l'échéance**, avec le tarif applicable et activation seulement après paiement. Une ancienne demande de rayon reste en lecture seule pour audit, sans action.
- `functions/index.js` : fonction d'email restaurée à son état validé après suppression du traitement des statuts de rayon. Les deux fichiers Node devenus inutiles de notification de rayon ont été supprimés.
- `advertising_spot_section.dart` : impossible de sélectionner ou soumettre un autre rayon depuis la modification d'une campagne approuvée ; seules les données `assetChangeRequest` liées au visuel et à la position sont écrites. Le choix initial d'une zone reste possible avant souscription.
- Clause CGV annonceur adaptée : verrouillage du rayon pendant toute période payée et possibilité de nouveau choix uniquement lors de la nouvelle souscription ; aucun visa du Super Admin. Le document `legalDocuments/advertiserCgv` déjà présent dans Firestore **n'est pas modifié automatiquement** : publication de la nouvelle clause et incrément de version à effectuer/contrôler depuis le Super Admin avant mise en production.
- Raccordement automatique d'une **nouvelle souscription payée** à l'activation du nouveau rayon : ne pas déclarer opérationnel sans tests de renouvellement et de paiement ; l'éditeur de campagne en cours n'offre volontairement plus ce changement.

Agencement du volet droit Super Admin demandé explicitement :
1. En-tête annonceur, visuel actuel en pleine largeur, bouton AGRANDIR.
2. Accordéon **ADMINISTRATION** replié initialement : toutes les informations de contact, structure, registre, documents acceptés, adresse et site.
3. Carte **DERNIÈRE MODIFICATION** affichée hors accordéon si statut existant, avec motif et décision ; si proposition visuel/position `submitted`, la comparaison AVANT/APRÈS reste visible ici.
4. Accordéon **HISTORIQUE DES MODIFICATIONS** replié initialement, reprenant sans supprimer les anciens dossiers visuel/position et les anciennes demandes de rayon (lecture seule).
5. Les trois boutons APPROUVER / DEMANDER UNE MODIFICATION / REFUSER existants et leurs conditions de disponibilité sont conservés en bas du volet.

**Avant validation** : récupération de `main`, `flutter analyze` sur fichiers modifiés, `flutter build web --release -t lib/main.dart`, test manuel `flutter run -d chrome -t lib/main.dart` et vérification du circuit visuel/position. Ne pas prétendre avoir exécuté Flutter ou effectué Hosting/Firebase depuis GitHub. Conserver `main` comme seul référentiel, vérifier les non-régressions avant tout autre push et déploiement.

## Validation visuelle finale du volet SPHOT PUBLICITAIRE — 20/10/2026

**Validation explicite de l'utilisateur après test sur Chrome de `main`**, avec capture du volet droit « BAR DE LA PLAGE ».

Éléments vérifiés visuellement et acceptés dans leur disposition actuelle :
- En-tête « BAR DE LA PLAGE » avec icône et fermeture.
- Bannière « SURF SHOP ATLANTIQUE » en haut du volet et bouton « AGRANDIR LE VISUEL ».
- Menu repliable « ADMINISTRATION », directement sous le visuel.
- Encadré visible « DERNIÈRE MODIFICATION » : dans ce cas de test historique, « CHANGEMENT DE RAYON REFUSÉ », comparaison 15 km → 5 km et motif du refus. **Il s'agit d'un dossier historique affiché en lecture seule, non d'un droit d'approuver à nouveau le rayon.**
- Menu repliable « HISTORIQUE DES MODIFICATIONS », placé après le dernier événement.
- Les trois commandes existantes sont conservées au bas du volet : APPROUVER LA DEMANDE, DEMANDER UNE MODIFICATION et REFUSER LA DEMANDE, avec leur état actuel (sur le dossier photographié, « DEMANDE REFUSÉE »).

**Statut : mise en page VALIDÉE — ne pas réorganiser de nouveau sans demande explicite.**

Référence du code Flutter `main` validé : `c35471e67c076d117f4c599d496f0c51f8906f7c` (avant ajout de ce compte-rendu documentaire). Aucun code d'interface n'est changé par l'enregistrement de la validation.

Le test visuel du volet ne constitue pas une validation du futur renouvellement payant, de la publication des CGV dans Firestore ou de la mise en production de la nouvelle version Web. À contrôler séparément.
