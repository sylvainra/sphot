# Corpus juridique SPHOT — intégration C4 TEST (non publié)

Ce dossier contient les versions françaises consolidées des CGV SPHOT ADMIN,
CGV SPHOT PUBLICITAIRE, CGU GRAND PUBLIC, CGU SPHOT SAUVETEUR et de la charte
professionnelle SPHOT SAUVETEUR. Les textes sont encore des **brouillons** :
ils ne constituent ni des CGV publiées ni une autorisation d'encaisser.

Les articles sur la clôture, la transmission sécurisée et la conservation
jusqu'au 31 décembre de la main courante ont été ajoutés **aux seuls brouillons
de test** ADMIN / SAUVETEUR. Ils ne déclenchent aucune clôture technique.

Le tableau de bord Super Admin affiche l'éditeur correspondant seulement si :

- le projet Firebase actif est `sphot-c4-test-20261029` ;
- le build Flutter porte `--dart-define=SPHOT_LEGAL_TEST_MODE=true` ;
- le compte utilisateur est authentifié et dispose des droits Firestore adaptés.

L'import est **manuel, document par document**. Un document distant existant
ne peut pas être écrasé lors de l'import. Toutes les versions enregistrées par
la suite sont propres au projet C4, marquées `testOnly: true`,
`published: false`, et les états précédents sont archivés dans
`legalTestCorpus/{documentId}/versions`. La collection est volontairement
**distincte de `legalDocuments`**, utilisée par les parcours existants ; les
CGV de test ne peuvent donc pas être confondues avec des CGV publiées.

Ne **pas** activer la lecture de ces documents dans les parcours d'acceptation,
les commandes, la facturation ou les paiements. Ne pas utiliser ce corpus pour
modifier Firestore `sphot-ab80b`, ni pour migrer les profils sauveteurs de test.

Après validation du dispositif, il restera à : mettre en cohérence les CGU,
PDC et Notices RGPD par audience ; établir les mentions légales de l'entité
SPHOT ; contrôler les règles Firestore du projet de test ; vérifier l'édition
dans Flutter ; puis réaliser les phases d'acceptation et de paiement de façon
isolée. Toute publication commerciale exige une décision distincte.
