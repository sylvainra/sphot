# SPHOT SAUVETEUR — STATS : base de reprise du 17 novembre 2026

**Statut : validation visuelle acceptée sur émulateur Android ; intégration Firebase préparée, non déployée.**

## Périmètre validé

- Chaque carte journalière garde VERT / JAUNE / ROUGE et présente, si nécessaire,
  INCIDENTS / INTERVENTIONS / RECHERCHES distinctes.
- Aucun doublon de ces trois catégories dans la rubrique FAITS ; les autres
  catégories et qualifications de secours restent consultables.
- Bouton « VOIR LES BILANS » sous la navigation mensuelle, défilement vers le
  bilan mensuel puis le bilan saisonnier ; bouton « PARTAGER » conservé.
- La flèche vers un mois futur est désactivée.
- Bilan mensuel par poste et bilan saisonnier couvrant l'union des périodes de
  surveillance affectées à ce poste dans une même année civile, y compris
  périodes discontinues ou chevauchantes.
- L'export PDF inclut les deux bilans et les trois nouveaux indicateurs.
- En attente de mise à jour serveur, les bilans journalier/mensuel restent
  affichables ; le bilan saisonnier signale la dépendance Firebase au lieu
  d'afficher un zéro trompeur.

## Validation documentée

Le 17/11/2026, l'utilisateur a confirmé la présentation satisfaisante sur
l'émulateur Android : navigation mensuelle, bouton « VOIR LES BILANS »,
défilement, compteur mensuel et emplacement du PDF.

Contrôles CI du chantier :
- Node/Firebase : lint, syntaxe, tests stats et cycle de vie.
- Flutter : analyse statique, 16 tests (STATS, drapeaux, préparation).
- Android : APK debug compilé avec succès (Flutter 3.47.7, Java 17 et Gradle
  du projet 8.14), sans installation ni publication.
- Les tests ci-dessus portent sur le code du dépôt ; ils ne remplacent pas un
  essai métier avec des faits réels et un backend raccordé.

## Sources et références Git

- Dépôt : `Sylvainra/SPHOT`
- PR de travail (non fusionnée) : `https://github.com/Sylvainra/SPHOT/pull/51`
- Branche : `codex/sauveteur-stats-saison-20261117`
- Point de départ initial : `5580e2278bdfbea5521335960644f6c73d393ed6`
- Version UI compatible avec Firebase ancien :
  `f876d4f00011e4e74f562898ffd6989e548eabf3`
- La tête de branche incluant les scripts et cette note constitue la source
  de reprise de ce chantier ; noter son SHA à chaque validation ultérieure.

## Raccordement Firebase : changements EXACTS

Fonctions à déployer ensemble après fusion et tests :
- `getSauveteurStats` : vérifie la session et le poste, retourne les faits
  paginés de l'année courante, limite les données privées renvoyées et ajoute
  `seasonPeriods: [{startDay: YYYYMMDD, endDay: YYYYMMDD}, ...]` pour les périodes
  attribuées au poste.
- `updateSauveteurLiveState` : attribue un `searchCaseId` lors d'une
  publication de recherche, le réutilise lors de republications tant que la
  notification de recherche reste active et l'enregistre en main courante.
- Nouveau helper autonome :
  `functions/sauveteur_stats_support.js`.
- Tests :
  `functions/test/sauveteur_stats_bilans.test.js`.

**Ne pas déployer `functions/index.js` tel quel depuis GitHub ou écraser
le fichier local.** La machine locale de développement contient des
modifications NON COMMITÉES de `functions/index.js`, d'Odoo, des
abonnements Admin et du juridique, absentes du commit de référence GitHub.
`firebase deploy --only functions:getSauveteurStats,functions:updateSauveteurLiveState`
doit être lancé uniquement depuis une copie locale fusionnée, contrôlée,
et sur le projet Firebase explicitement vérifié. Les autres fonctions
ne doivent pas être ciblées.

### Fusion locale sans écraser les autres chantiers (PowerShell)

Dans `C:\Users\surfS\sphot`, **sans changer de branche ni faire de stash** :

```powershell
git fetch origin codex/sauveteur-stats-saison-20261117
git restore --source=FETCH_HEAD --worktree -- tools/sphot_stats_safe_merge.js
node tools/sphot_stats_safe_merge.js --check
```

Si le contrôle indique « PRÉCONTRÔLE OK », lancer :

```powershell
node tools/sphot_stats_safe_merge.js --apply
node --check functions/index.js
npm --prefix functions run lint
node --test functions/test/sauveteur_stats_bilans.test.js
git diff --check
git diff -- functions/index.js
```

Le script tente d'abord un merge Git à trois versions. Si ce merge
signale des conflits (notamment avec le travail local Odoo/Admin), il utilise
une **fusion ciblée** de l'import, de la fonction getSauveteurStats et
des deux insertions d'identifiant dans updateSauveteurLiveState.
Le diagnostic local du 17/11/2026 a identifié exactement deux variantes
de getSauveteurStats par rapport au commit initial :
- autorisation `context.realtimeSpotIds.includes(spotId)` plutôt que
  `assignedSpotIds` et `supervisedSpotIds` séparés (le contexte realtime
  est lui-même restreint aux postes affectés, supervisés et autorisés) ;
- requête filtrée sur `dayStartMillis/dayEndMillis` avec `limit(500)`
  plutôt que `mainCouranteReadBounds`.

La version cible STATS conserve la règle `realtimeSpotIds`, applique
`mainCouranteReadBounds` et effectue la pagination des faits.
Une variante locale n'est acceptée que si elle correspond strictement
à ces deux différences ; toute autre différence de la fonction STATS
stoppe l'opération, sans écrasement.

Le diagnostic complémentaire du même jour montre que la fonction locale
`updateSauveteurLiveState` lit directement le document SPHOT par
`spotReference.get()` puis sauvegarde avec `batch.commit()`, alors que
le code de la branche d'essai utilise `db.runTransaction`.
La fusion de secours **ne remplace pas ce fonctionnement local** :
elle ajoute uniquement la création/réutilisation de `searchCaseId`
après la lecture du SPHOT, sa mémorisation dans `notificationPublique`
et le même identifiant dans l'inscription `mainCourante`.
Elle exige des ancres structurelles uniques et s'arrête si elles diffèrent.
Cette intégration locale par lecture + batch ne garantit pas la réutilisation
d'un identifiant en cas de deux premières publications réellement
concurrentes ; cette limite doit être testée et corrigée séparément si
des publications simultanées sont possibles.

Avant toute écriture, le script vérifie que son calcul reproduit EXACTEMENT
le commit STATS cible depuis le commit initial.
Il conserve une sauvegarde dans le répertoire temporaire du système et
refuse d'écraser un fichier auxiliaire déjà différent. En cas de refus,
**ne pas forcer** le déploiement : examiner le message et réaliser une
résolution localisée.

**Contrôle avant déploiement :** vérifier le projet Firebase sélectionné,
le statut du merge et les tests, puis effectuer un déploiement strictement
limité aux deux fonctions indiquées ci-dessus. Ne jamais déployer
`functions` entier, les règles Firestore ou le hosting dans ce chantier.

## Vérifications indispensables après raccordement

1. Sur l'émulateur sauveteur connecté, ouvrir STATS, cliquer « VOIR LES
   BILANS » ; confirmer que le message « mise à jour serveur nécessaire »
   disparaît et que les périodes réelles correspondent au poste affecté.
2. Sur une journée de test autorisée : créer un incident et une intervention,
   vérifier leurs compteurs sans double ligne dans FAITS.
3. Publier puis republier la même recherche active : nombre de recherches
   distinctes inchangé ; après clôture, une nouvelle recherche doit
   augmenter le total.
4. Vérifier plusieurs périodes non contiguës et les frontières du calendrier.
5. Tester un PDF mensuel et saisonnier, ainsi que les droits liés aux
   informations restreintes.
6. Vérifier une seconde fois que toutes les fonctions Admin/Odoo et les
   dossiers juridiques locaux sont inchangés.

## Limitations documentées, à traiter séparément

- Les anciennes recherches sans `searchCaseId` restent comptées
  individuellement ; il n'existe pas de rapprochement automatique fondé sur
  l'identité d'une personne.
- Pour une deuxième recherche alors que la première notification reste
  active, un mécanisme explicite « nouvelle recherche » devra être ajouté
  pour garantir une séparation parfaite des dossiers simultanés.
- Les affectations de périodes consultées sont celles disponibles au
  moment du bilan ; l'archivage historique des affectations doit être conçu
  séparément pour préserver les saisons après modification du personnel.
- La main courante est aujourd'hui purgée au changement d'année : conserver
  des bilans saisonniers des années précédentes nécessitera un mécanisme
  d'archivage de totaux non sensibles, avant purge.
- Le déploiement effectif, la fusion en `main`, le push de tous les travaux
  locaux Admin/Odoo et la validation de chiffres réels ne sont PAS réalisés
  par ce document.

## Discipline pour les prochaines évolutions

Toujours repartir de la tête de la branche de reprise et du dernier état
local validé, sans effacer les chantiers parallèles. Préserver les éléments
visuels validés, vérifier le différentiel et exécuter les tests avant
toute fusion ou publication. Tout commit et déploiement doivent être
consignés avec les résultats du test réel.
