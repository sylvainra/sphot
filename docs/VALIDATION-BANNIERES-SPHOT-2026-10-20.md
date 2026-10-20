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

## Nettoyage / suivi du déploiement

Suppressions du dépôt : cache local `.firebase/hosting.YnVpbGRcd2Vi.cache`, fichier de configuration d'émulateur publicitaire isolé, règles d'émulateur dédiées, deux scripts d'essai local isolé et ancien mode d'emploi associé. `.firebase/` est ignoré par Git ; les tests unitaires utiles à la projection publique sont conservés dans `functions/test/`.

Ne pas confondre suppression de fichiers de test versionnés et suppression d'un site Firebase, d'un projet Firebase, de Firestore ou de Storage : aucune donnée distante ne doit être détruite sans inventaire et validation explicite.

Le commit GitHub et la validation des captures ne constituent **pas** un déploiement Firebase Hosting. Procédure de déploiement à effectuer sur le PC après synchronisation de `main` : vérification Flutter, build Web de production, puis `firebase deploy --only hosting --project sphot-ab80b`, avec confirmation du site cible. Ne pas déployer les Cloud Functions pour cet ajustement UI.
